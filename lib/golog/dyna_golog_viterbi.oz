%% SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
%% CLONE_GATE: dyna_golog_viterbi_oz
%%
%% DYNA-GOLOG v2.0 — Viterbi Semiring Application
%% Raw Logic Engineering Artifact — Oz/Mozart
%% Author: Ahmad <ahmedparr93@gmail.com>
%%
%% Faithful reconstruction in Oz (Mozart/Oz 3). Oz's constraint-based,
%% logic/functional core maps naturally onto the Dyna/situation-calculus style.
%% Preserves: algebraic structure (Viterbi semiring), relational/memoized DP
%% engine, situation-calculus layer, GOLOG control constructs, three domain
%% models, and test driver.

functor
import
   System(show showln)
   Property
   Open
   OS
   Random

define

   %% =====================================================================
   %% 1. VITERBI SEMIRING (R, +, *, 0, 1) with + = max, * = product
   %% =====================================================================
   ViterbiSem = semiring(
      zero: 0.0
      one: 1.0
      add: fun {$ A B} if A >= B then A else B end end
      mul: fun {$ A B}
               if A =< 0.0 orelse B =< 0.0 then 0.0 else A * B end
            end
      isZero: fun {$ X} X =< 0.0 end
      isOne: fun {$ X} {Abs X - 1.0} < 1.0e~15 end
   )

   LogViterbiSem = semiring(
      zero: ~1.0e300
      one: 0.0
      add: fun {$ A B} if A >= B then A else B end end
      mul: fun {$ A B}
               if A =< ~1.0e299 orelse B =< ~1.0e299 then ~1.0e300
               else A + B end
            end
      isZero: fun {$ X} X =< ~1.0e299 end
      isOne: fun {$ X} {Abs X} < 1.0e~15 end
   )

   fun {ToLog P} if P =< 0.0 then ~1.0e300 else {Log P} end end
   fun {FromLog L}
      if L =< ~1.0e299 then 0.0
      else {Exp L} end
   end

   %% =====================================================================
   %% 2. MEMO TABLE AND RELATION
   %% =====================================================================

   class MemoTable from BaseObject
      attr Store Epoch Hits Misses
      feat Name Sem

      meth init(Name Sem)
         Store := {NewDictionary}
         Epoch := 0
         Hits := 0
         Misses := 0
         Name := Name
         Sem := Sem
      end

      meth get(Key Default $)
         if {Dictionary.member @Store Key} then
            Hits := @Hits + 1
            {Dictionary.get @Store Key}
         else
            Misses := @Misses + 1
            Default
         end
      end

      meth put(Key Value)
         Old = {Dictionary.condGet @Store Key @Sem.zero}
         New = {@Sem.add Old Value}
      in
         {Dictionary.put @Store Key New}
      end

      meth putForce(Key Value)
         {Dictionary.put @Store Key Value}
      end

      meth contains(Key $)
         {Dictionary.member @Store Key}
      end

      meth items($)
         {Dictionary.items @Store}
      end

      meth keys($)
         {Dictionary.keys @Store}
      end

      meth clear()
         Store := {NewDictionary}
         Epoch := @Epoch + 1
      end

      meth size($) {Dictionary.size @Store} end

      meth stats($)
         stats(size: {Dictionary.size @Store}
               hits: @Hits misses: @Misses epoch: @Epoch)
      end
   end

   class Relation from BaseObject
      attr Ext Intens Name Arity Sem

      meth init(Name Arity Sem)
         Ext := {New MemoTable init(Name#'_ext' Sem)}
         Intens := {New MemoTable init(Name#'_int' Sem)}
         Name := Name
         Arity := Arity
         Sem := Sem
      end

      meth assertFact(Args Weight)
         if {Length Args} \= @Arity then
            raise arityMismatch(@Name @Arity {Length Args}) end
         end
         {@Ext put(Args Weight)}
      end

      meth derive(Args Weight)
         if {Length Args} \= @Arity then
            raise arityMismatch(@Name @Arity {Length Args}) end
         end
         {@Intens put(Args Weight)}
      end

      meth lookup(Args $)
         W = {@Intens get(Args @Sem.zero)}
      in
         if {@Sem.isZero W} then {@Ext get(Args @Sem.zero)}
         else W end
      end

      meth clearDerived() {@Intens clear()} end

      meth allFacts($)
         {Append {@Ext items} {@Intens items}}
      end
   end

   Registry = {NewDictionary}

   fun {RegisterRelation Name Arity Sem}
      if {Dictionary.member Registry Name} then
         {Dictionary.get Registry Name}
      else
         R = {New Relation init(Name Arity Sem)}
      in
         {Dictionary.put Registry Name R}
         R
      end
   end

   %% =====================================================================
   %% 3. HMM DOMAIN RELATIONS
   %% =====================================================================

   StartRel = {RegisterRelation 'start' 1 ViterbiSem}
   TransitionRel = {RegisterRelation 'transition' 2 ViterbiSem}
   EmissionRel = {RegisterRelation 'emission' 2 ViterbiSem}
   ObservationRel = {RegisterRelation 'observation' 2 ViterbiSem}
   PathWeightRel = {RegisterRelation 'path_weight' 2 ViterbiSem}

   Backpointers = {NewDictionary}

   proc {AssertStart Q P}
      if P < 0.0 orelse P > 1.0 then raise invalidProb(P) end end
      {StartRel assertFact([Q] P)}
   end

   proc {AssertTransition Q1 Q2 P}
      if P < 0.0 orelse P > 1.0 then raise invalidProb(P) end end
      {TransitionRel assertFact([Q1 Q2] P)}
   end

   proc {AssertEmission Q O P}
      if P < 0.0 orelse P > 1.0 then raise invalidProb(P) end end
      {EmissionRel assertFact([Q O] P)}
   end

   proc {AssertObservation T O}
      {ObservationRel assertFact([T O] ViterbiSem.one)}
   end

   %% =====================================================================
   %% 4. VITERBI RECURRENCE (DYNA RULES)
   %% =====================================================================

   fun {FindObs T}
      Result = {NewCell unit}
   in
      for (Key#_) in {ObservationRel allFacts($)} do
         if {List.nth Key 1} == T then
            Result := {List.nth Key 2}
         end
      end
      @Result
   end

   proc {ViterbiInitialize States}
      {PathWeightRel clearDerived()}
      {Dictionary.removeAll Backpointers}
      for Q in States do
         SW = {StartRel lookup([Q] $)}
      in
         if {Not {ViterbiSem.isZero SW}} then
            ObsSym = {FindObs 0}
         in
            if ObsSym \= unit then
               EW = {EmissionRel lookup([Q ObsSym] $)}
               W = {ViterbiSem.mul SW EW}
            in
               if {Not {ViterbiSem.isZero W}} then
                  {PathWeightRel derive([0 Q] W)}
                  {Dictionary.put Backpointers (0#Q) unit}
               end
            end
         end
      end
   end

   proc {ViterbiStep T States}
      ObsSym = {FindObs T}
   in
      if ObsSym == unit then
         raise noObservation(T) end
      end
      for Q in States do
         BestW = {NewCell ViterbiSem.zero}
         BestPrev = {NewCell unit}
      in
         for QPrev in States do
            PrevW = {PathWeightRel lookup([T-1 QPrev] $)}
         in
            if {Not {ViterbiSem.isZero PrevW}} then
               TransW = {TransitionRel lookup([QPrev Q] $)}
            in
               if {Not {ViterbiSem.isZero TransW}} then
                  EmitW = {EmissionRel lookup([Q ObsSym] $)}
               in
                  if {Not {ViterbiSem.isZero EmitW}} then
                     Cand = {ViterbiSem.mul PrevW
                                {ViterbiSem.mul TransW EmitW}}
                  in
                     if Cand > @BestW then
                        BestW := Cand
                        BestPrev := QPrev
                     end
                  end
               end
            end
         end
         if {Not {ViterbiSem.isZero @BestW}} then
            {PathWeightRel derive([T Q] @BestW)}
            {Dictionary.put Backpointers (T#Q)
             (if @BestPrev == unit then unit else @BestPrev end)}
         end
      end
   end

   proc {ViterbiRun TMax States}
      {ViterbiInitialize States}
      for T in 1..(TMax-1) do
         {ViterbiStep T States}
      end
   end

   %% =====================================================================
   %% 5. PATH RECONSTRUCTION
   %% =====================================================================

   fun {ReconstructPath TMax States}
      BestFinal = {NewCell unit}
      BestW = {NewCell ViterbiSem.zero}
   in
      for Q in States do
         W = {PathWeightRel lookup([TMax-1 Q] $)}
      in
         if W > @BestW then
            BestW := W
            BestFinal := Q
         end
      end
      if @BestFinal == unit then []#ViterbiSem.zero
      else
         Path = {NewCell [@BestFinal]}
         T = {NewCell TMax-1}
         Cur = {NewCell @BestFinal}
      in
         {While @T > 0 do
             Prev = {Dictionary.condGet Backpointers (@T#@Cur) unit}
          in
             if Prev == unit then T := 0
             else
                Path := Prev|@Path
                Cur := Prev
                T := @T - 1
             end
          end}
         @Path # @BestW
      end
   end

   %% =====================================================================
   %% 6. SITUATION CALCULUS LAYER
   %% =====================================================================

   S0 = s0

   fun {Do Action Situation} do(action: Action s: Situation) end

   fun {SituationDepth S}
      case S of do(action:_ s:Rest) then 1 + {SituationDepth Rest}
      else 0 end
   end

   FluentStore = {NewDictionary}

   fun {Holds FName Sit Default}
      Key = FName#Sit
   in
      if {Dictionary.member FluentStore Key} then
         {Dictionary.get FluentStore Key}
      else
         case Sit of do(action:_ s:Rest) then
            {Holds FName Rest Default}
         else Default end
      end
   end

   proc {SetFluent FName Sit Value}
      {Dictionary.put FluentStore (FName#Sit) Value}
   end

   %% =====================================================================
   %% 7. ACTIONS AND PRECONDITIONS
   %% =====================================================================

   fun {MakeAction Name Args} action(name: Name args: Args) end

   fun {Poss Action Sit}
      case Action of action(name:N args:_) then
         case N
         of observe then true
         [] decode then
            {Length {Holds observations Sit nil}} > 0
         [] reset_model then true
         [] assert_start then true
         [] assert_transition then true
         [] assert_emission then true
         [] run_viterbi then
            {Length {Holds observations Sit nil}} > 0 andthen
            {Length {Holds states Sit nil}} > 0
         else false
         end
      end
   end

   %% =====================================================================
   %% 8. SUCCESSOR-STATE AXIOMS
   %% =====================================================================

   fun {SuccessorObservations Action Sit}
      Prev = {Holds observations Sit nil}
   in
      case Action of action(name:N args:A) then
         case N
         of observe then {Append Prev [{List.nth A 1}]}
         [] reset_model then nil
         else Prev
         end
      end
   end

   fun {SuccessorStates Action Sit}
      Prev = {Holds states Sit nil}
   in
      case Action of action(name:N args:_) then
         if N == reset_model then nil else Prev end
      end
   end

   fun {SuccessorPath Action Sit}
      case Action of action(name:N args:_) then
         case N
         of run_viterbi then {Holds last_path Sit unit}
         [] reset_model then unit
         else {Holds path Sit unit}
         end
      end
   end

   fun {SuccessorPathWeight Action Sit}
      case Action of action(name:N args:_) then
         case N
         of run_viterbi then {Holds last_weight Sit ViterbiSem.zero}
         [] reset_model then ViterbiSem.zero
         else {Holds path_weight Sit ViterbiSem.zero}
         end
      end
   end

   fun {ApplySuccessorAxioms Action Sit}
      if {Not {Poss Action Sit}} then
         raise actionNotPossible(Action Sit) end
      end
      NewSit = {Do Action Sit}
   in
      {SetFluent observations NewSit {SuccessorObservations Action Sit}}
      {SetFluent states NewSit {SuccessorStates Action Sit}}
      {SetFluent path NewSit {SuccessorPath Action Sit}}
      {SetFluent path_weight NewSit {SuccessorPathWeight Action Sit}}
      {SetFluent last_action NewSit Action}
      {SetFluent time NewSit {SituationDepth NewSit}}
      NewSit
   end

   %% =====================================================================
   %% 9. GOLOG CONTROL CONSTRUCTS
   %% =====================================================================

   fun {Seq Ps}
      case Ps of [P] then P
      [] P|Rest then seq(first: P second: {Seq Rest})
      end
   end

   fun {Choose Ps}
      case Ps of [P] then P
      [] P|Rest then choice(left: P right: {Choose Rest})
      end
   end

   fun {Star P} star(body: P) end
   fun {Test Cond} test(condition: Cond) end
   fun {Prim Action} prim(action: Action) end

   fun {ExecuteProg Prog Sit MaxSteps}
      Steps = {NewCell 0}

      fun {Rec P S}
         if @Steps >= MaxSteps then
            raise gologOverflow(@Steps) end
         end
         Steps := @Steps + 1
         case P
         of prim(action:A) then {ApplySuccessorAxioms A S}
         [] seq(first:P1 second:P2) then
            S1 = {Rec P1 S}
         in
            {Rec P2 S1}
         [] choice(left:P1 right:P2) then
            try {Rec P1 S} catch _ then {Rec P2 S} end
         [] star(body:B) then
            {Unroll B S 8}
         [] test(condition:C) then
            if {C S} then S else raise testFailed end end
         end
      end

      fun {Unroll B S N}
         if N =< 0 then S
         else
            try
               S1 = {Rec B S}
            in
               {Unroll B S1 N-1}
            catch _ then S end
         end
      end
   in
      {Rec Prog Sit}
   end

   %% =====================================================================
   %% 10. DOMAIN MODELS
   %% =====================================================================

   RelationNames = ['start' 'transition' 'emission' 'observation' 'path_weight']

   proc {ClearEverything}
      {Dictionary.removeAll Registry}
      {Dictionary.removeAll FluentStore}
      {Dictionary.removeAll Backpointers}
   end

   fun {LoadToyWeather}
      States = ['Sunny' 'Rainy']
      Start = {RegisterRelation 'start' 1 ViterbiSem}
      Trans = {RegisterRelation 'transition' 2 ViterbiSem}
      Emit = {RegisterRelation 'emission' 2 ViterbiSem}
   in
      {Start assertFact(['Sunny'] 0.6)}
      {Start assertFact(['Rainy'] 0.4)}
      {Trans assertFact(['Sunny' 'Sunny'] 0.7)}
      {Trans assertFact(['Sunny' 'Rainy'] 0.3)}
      {Trans assertFact(['Rainy' 'Sunny'] 0.4)}
      {Trans assertFact(['Rainy' 'Rainy'] 0.6)}
      {Emit assertFact(['Sunny' walk] 0.1)}
      {Emit assertFact(['Sunny' shop] 0.4)}
      {Emit assertFact(['Sunny' clean] 0.5)}
      {Emit assertFact(['Rainy' walk] 0.6)}
      {Emit assertFact(['Rainy' shop] 0.3)}
      {Emit assertFact(['Rainy' clean] 0.1)}
      States
   end

   fun {LoadPOSTagger}
      States = ['DET' 'NN' 'VB' 'IN' 'PUNCT']
      Start = {RegisterRelation 'start' 1 ViterbiSem}
      Trans = {RegisterRelation 'transition' 2 ViterbiSem}
      Emit = {RegisterRelation 'emission' 2 ViterbiSem}
      N = {IntToFloat {Length States}}
   in
      for S in States do {Start assertFact([S] 1.0/N)} end
      TransData = [
         ['DET' 'NN' 0.8] ['DET' 'VB' 0.05] ['DET' 'IN' 0.05]
         ['DET' 'DET' 0.05] ['DET' 'PUNCT' 0.05]
         ['NN' 'VB' 0.4] ['NN' 'IN' 0.3] ['NN' 'PUNCT' 0.2]
         ['NN' 'NN' 0.05] ['NN' 'DET' 0.05]
         ['VB' 'DET' 0.3] ['VB' 'NN' 0.2] ['VB' 'IN' 0.3]
         ['VB' 'PUNCT' 0.15] ['VB' 'VB' 0.05]
         ['IN' 'DET' 0.6] ['IN' 'NN' 0.3] ['IN' 'PUNCT' 0.05]
         ['IN' 'VB' 0.03] ['IN' 'IN' 0.02]
         ['PUNCT' 'DET' 0.4] ['PUNCT' 'NN' 0.3] ['PUNCT' 'VB' 0.2]
         ['PUNCT' 'IN' 0.05] ['PUNCT' 'PUNCT' 0.05]
      ]
      for [Q1 Q2 P] in TransData do
         {Trans assertFact([Q1 Q2] P)}
      end
      EmitData = [
         ['DET' 'the' 0.6] ['DET' 'a' 0.3] ['DET' 'an' 0.1]
         ['NN' 'cat' 0.2] ['NN' 'dog' 0.2] ['NN' 'man' 0.15]
         ['NN' 'woman' 0.15] ['NN' 'park' 0.1] ['NN' 'house' 0.1]
         ['NN' 'car' 0.1]
         ['VB' 'saw' 0.25] ['VB' 'walked' 0.25] ['VB' 'ate' 0.2]
         ['VB' 'ran' 0.15] ['VB' 'is' 0.15]
         ['IN' 'in' 0.4] ['IN' 'on' 0.3] ['IN' 'with' 0.2]
         ['IN' 'by' 0.1]
         ['PUNCT' '.' 0.7] ['PUNCT' '!' 0.2] ['PUNCT' '?' 0.1]
      ]
      Vocab = {NewDictionary}
      for [Q O P] in EmitData do
         {Emit assertFact([Q O] P)}
         {Dictionary.put Vocab O unit}
      end
      for Q in States do
         for O in {Dictionary.keys Vocab} do
            if {ViterbiSem.isZero {Emit lookup([Q O] $)}} then
               {Emit assertFact([Q O] 1.0e~6)}
            end
         end
      end
      States
   end

   fun {LoadCpG}
      States = ['Island' 'Ocean']
      Start = {RegisterRelation 'start' 1 ViterbiSem}
      Trans = {RegisterRelation 'transition' 2 ViterbiSem}
      Emit = {RegisterRelation 'emission' 2 ViterbiSem}
   in
      {Start assertFact(['Island'] 0.2)}
      {Start assertFact(['Ocean'] 0.8)}
      {Trans assertFact(['Island' 'Island'] 0.95)}
      {Trans assertFact(['Island' 'Ocean'] 0.05)}
      {Trans assertFact(['Ocean' 'Ocean'] 0.95)}
      {Trans assertFact(['Ocean' 'Island'] 0.05)}
      {Emit assertFact(['Island' 'A'] 0.15)}
      {Emit assertFact(['Island' 'C'] 0.35)}
      {Emit assertFact(['Island' 'G'] 0.35)}
      {Emit assertFact(['Island' 'T'] 0.15)}
      {Emit assertFact(['Ocean' 'A'] 0.30)}
      {Emit assertFact(['Ocean' 'C'] 0.20)}
      {Emit assertFact(['Ocean' 'G'] 0.20)}
      {Emit assertFact(['Ocean' 'T'] 0.30)}
      States
   end

   %% =====================================================================
   %% 11. LATTICE DECODING
   %% =====================================================================

   class Lattice from BaseObject
      attr Nodes Edges Starts Ends

      meth init()
         Nodes := {NewDictionary}
         Edges := {NewCell nil}
         Starts := {NewCell nil}
         Ends := {NewCell nil}
      end

      meth addNode(Id Time Label)
         {Dictionary.put @Nodes Id node(id:Id time:Time label:Label)}
      end

      meth addEdge(Src Tgt Weight Symbol)
         Edges := latticeEdge(src:Src tgt:Tgt w:Weight sym:Symbol)|@Edges
      end

      meth setStart(Ids) Starts := Ids end
      meth setEnd(Ids) Ends := Ids end

      meth viterbiDecode($)
         Best = {NewDictionary}
         Back = {NewDictionary}
      in
         for Id in {Dictionary.keys @Nodes} do
            {Dictionary.put Best Id ViterbiSem.zero}
            {Dictionary.put Back Id unit}
         end
         for Id in @Starts do {Dictionary.put Best Id ViterbiSem.one} end

         Ordered = {Sort {Dictionary.keys @Nodes}
                    fun {$ A B}
                       {Dictionary.get @Nodes A}.time =<
                       {Dictionary.get @Nodes B}.time
                    end}
         for Id in Ordered do
            BW = {Dictionary.get Best Id}
         in
            if {Not {ViterbiSem.isZero BW}} then
               for E in @Edges do
                  if E.src == Id then
                     Cand = {ViterbiSem.mul BW E.w}
                     Old = {Dictionary.get Best E.tgt}
                  in
                     if Cand > Old then
                        {Dictionary.put Best E.tgt Cand}
                        {Dictionary.put Back E.tgt Id}
                     end
                  end
               end
            end
         end

         BestEnd = {NewCell unit}
         BestW = {NewCell ViterbiSem.zero}
      in
         for Id in @Ends do
            W = {Dictionary.get Best Id}
         in
            if W > @BestW then BestW := W BestEnd := Id end
         end
         if @BestEnd == unit then []#ViterbiSem.zero
         else
            Path = {NewCell nil}
            Cur = {NewCell @BestEnd}
         in
            {While @Cur \= unit do
                Path := @Cur|@Path
                Cur := {Dictionary.get Back @Cur}
             end}
            @Path # @BestW
         end
      end
   end

   %% =====================================================================
   %% 12. LOG-DOMAIN VITERBI
   %% =====================================================================

   fun {ViterbiLogDomain TMax States}
      LogStart = {NewDictionary}
      LogTrans = {NewDictionary}
   in
      for Q in States do
         {Dictionary.put LogStart Q {ToLog {StartRel lookup([Q] $)}}}
      end
      for Q1 in States do for Q2 in States do
         {Dictionary.put LogTrans (Q1#Q2)
          {ToLog {TransitionRel lookup([Q1 Q2] $)}}}
      end end

      V = {List.make TMax}
      BP = {List.make TMax}
      for I in 1..TMax do
         V.I := {NewDictionary}
         BP.I := {NewDictionary}
      end

      Obs0 = {FindObs 0}
   in
      for Q in States do
         {Dictionary.put V.1 Q
          {LogViterbiSem.mul {Dictionary.get LogStart Q}
           {ToLog {EmissionRel lookup([Q Obs0] $)}}}}
         {Dictionary.put BP.1 Q unit}
      end

      for T in 2..TMax do
         Obs = {FindObs T-1}
      in
         for Q in States do
            Best = {NewCell LogViterbiSem.zero}
            BestPrev = {NewCell unit}
         in
            for QPrev in States do
               Cand = {LogViterbiSem.mul
                          {Dictionary.get V.(T-1) QPrev}
                          {LogViterbiSem.mul
                              {Dictionary.get LogTrans (QPrev#Q)}
                              {ToLog {EmissionRel lookup([Q Obs] $)}}}}
            in
               if Cand > @Best then
                  Best := Cand
                  BestPrev := QPrev
               end
            end
            {Dictionary.put V.T Q @Best}
            {Dictionary.put BP.T Q @BestPrev}
         end
      end

      BestFinal = {NewCell unit}
      BestVal = {NewCell LogViterbiSem.zero}
   in
      for Q in States do
         W = {Dictionary.get V.TMax Q}
      in
         if W > @BestVal then BestVal := W BestFinal := Q end
      end

      Path = {NewCell [@BestFinal]}
      for T in TMax..2;~1 do
         Prev = {Dictionary.get BP.T Path.1}
      in
         if Prev \= unit then Path := Prev|@Path end
      end
      @Path # @BestVal
   end

   %% =====================================================================
   %% 13. VERIFICATION AND TESTS
   %% =====================================================================

   fun {VerifySemiringAxioms Trials}
      Rand = {New Random.init(42)}
   in
      for _ in 1..Trials do
         A = {Rand.uniformReal}
         B = {Rand.uniformReal}
         C = {Rand.uniformReal}
      in
         if {Abs {ViterbiSem.add A B} - {ViterbiSem.add B A}} > 1.0e~12 then
            raise semiringFail(commAdd) end end
         if {Abs {ViterbiSem.add {ViterbiSem.add A B} C} -
                 {ViterbiSem.add A {ViterbiSem.add B C}}} > 1.0e~12 then
            raise semiringFail(assocAdd) end end
         if {Abs {ViterbiSem.mul A B} - {ViterbiSem.mul B A}} > 1.0e~12 then
            raise semiringFail(commMul) end end
         if {Abs {ViterbiSem.mul {ViterbiSem.mul A B} C} -
                 {ViterbiSem.mul A {ViterbiSem.mul B C}}} > 1.0e~12 then
            raise semiringFail(assocMul) end end
         L = {ViterbiSem.mul A {ViterbiSem.add B C}}
         R = {ViterbiSem.add {ViterbiSem.mul A B} {ViterbiSem.mul A C}}
      in
         if {Abs L - R} > 1.0e~12 then raise semiringFail(distrib) end end
         if {Abs {ViterbiSem.add A ViterbiSem.zero} - A} > 1.0e~12 then
            raise semiringFail(addId) end end
         if {Abs {ViterbiSem.mul A ViterbiSem.one} - A} > 1.0e~12 then
            raise semiringFail(mulId) end end
         if {Abs {ViterbiSem.mul A ViterbiSem.zero} - ViterbiSem.zero}
            > 1.0e~12 then raise semiringFail(annihil) end end
      end
      true
   end

   proc {TestToyWeather}
      {ClearEverything}
      States = {LoadToyWeather}
      Obs = [walk shop walk]
   in
      for T in 0..({Length Obs}-1) do
         {AssertObservation T {List.nth Obs T+1}}
      end
      {ViterbiRun {Length Obs} States}
      Path#W = {ReconstructPath {Length Obs} States}
   in
      if {Length Path} \= 3 then raise testFailed end end
      {System.show '[PASS] test_toy_weather'#path:Path#weight:W}
   end

   proc {TestLogDomainAgreement}
      {ClearEverything}
      States = {LoadToyWeather}
      Obs = [walk shop clean walk]
   in
      for T in 0..({Length Obs}-1) do
         {AssertObservation T {List.nth Obs T+1}}
      end
      {ViterbiRun {Length Obs} States}
      Path1#W1 = {ReconstructPath {Length Obs} States}
      Path2#LogW2 = {ViterbiLogDomain {Length Obs} States}
      W2 = {FromLog LogW2}
   in
      if Path1 \= Path2 then raise pathsDiffer end end
      if {Abs W1 - W2} > 1.0e~9 then raise weightsDiffer end end
      {System.show '[PASS] test_log_domain_agreement'}
   end

   proc {TestGologObserveDecode}
      {ClearEverything}
      _ = {LoadToyWeather}
      {SetFluent observations S0 nil}
      {SetFluent states S0 ['Sunny' 'Rainy']}
      {SetFluent path S0 unit}
      {SetFluent path_weight S0 0.0}
      Prog = {Seq [ {Prim {MakeAction observe ['walk']}}
                    {Prim {MakeAction observe ['shop']}}
                    {Prim {MakeAction observe ['walk']}}
                    {Prim {MakeAction run_viterbi []}} ]}
      Final = {ExecuteProg Prog S0 1000}
      Obs = {Holds observations Final nil}
   in
      if Obs \= [walk shop walk] then raise testFailed(obs Obs) end end
      {System.show '[PASS] test_golog_observe_decode'}
   end

   proc {TestLatticeDecode}
      L = {New Lattice init()}
   in
      {L addNode(0 0 unit)}
      {L addNode(1 1 unit)}
      {L addNode(2 1 unit)}
      {L addNode(3 2 unit)}
      {L setStart([0])}
      {L setEnd([3])}
      {L addEdge(0 1 0.6 'a')}
      {L addEdge(0 2 0.4 'b')}
      {L addEdge(1 3 0.7 'c')}
      {L addEdge(2 3 0.9 'd')}
      Path#W = {L viterbiDecode($)}
   in
      if Path \= [0 2 3] then raise pathFailed(Path) end end
      if {Abs W - 0.36} > 1.0e~9 then raise weightFailed(W) end end
      {System.show '[PASS] test_lattice_decode'}
   end

   proc {TestPOSTagger}
      {ClearEverything}
      States = {LoadPOSTagger}
      Sentence = ['the' 'cat' 'saw' 'the' 'dog' '.']
   in
      for T in 0..({Length Sentence}-1) do
         {AssertObservation T {List.nth Sentence T+1}}
      end
      {ViterbiRun {Length Sentence} States}
      Path#W = {ReconstructPath {Length Sentence} States}
   in
      if {Length Path} \= {Length Sentence} then raise testFailed end end
      {System.show '[PASS] test_pos_tagger_smoke'#path:Path#weight:W}
   end

   proc {TestCpG}
      {ClearEverything}
      States = {LoadCpG}
      Seq = "CGCGCGATATCGCGCG"
      L = {String.length Seq}
   in
      for T in 0..(L-1) do
         {AssertObservation T {String.toAtom [Seq.T+1]}}
      end
      {ViterbiRun L States}
      Path#W = {ReconstructPath L States}
   in
      if {Length Path} \= L then raise testFailed end end
      {System.show '[PASS] test_cpg_island_smoke'#path:Path#weight:W}
   end

   proc {RunAllTests}
      {System.show '============================================================'}
      {System.show 'RUNNING EXHAUSTIVE TEST SUITE'}
      {System.show '============================================================'}
      _ = {VerifySemiringAxioms 200}
      {System.show '[PASS] test_semiring_axioms'}
      {TestToyWeather}
      {TestLogDomainAgreement}
      {TestGologObserveDecode}
      {TestLatticeDecode}
      {TestPOSTagger}
      {TestCpG}
      {System.show '============================================================'}
      {System.show 'ALL TESTS PASSED'}
      {System.show '============================================================'}
   end

   %% =====================================================================
   %% 14. MAIN DRIVER
   %% =====================================================================

   proc {Main}
      {System.show 'DYNA-GOLOG Viterbi Semiring Application'}
      {System.show 'Raw Logic Engineering Artifact — Oz/Mozart'}
      {System.show '------------------------------------------------------------'}

      _ = {VerifySemiringAxioms 200}
      {System.show 'Semiring axioms verified.'}

      {RunAllTests}

      {System.show ''}
      {System.show '*** DEMO: Toy Weather HMM ***'}
      {ClearEverything}
      local States = {LoadToyWeather}
            Obs = [walk shop walk clean walk]
      in
         for T in 0..({Length Obs}-1) do
            {AssertObservation T {List.nth Obs T+1}}
         end
         {ViterbiRun {Length Obs} States}
         Path#W = {ReconstructPath {Length Obs} States}
      in
         {System.show 'Observations:'#Obs}
         {System.show 'Most probable state sequence:'#Path}
         {System.show 'Path probability:'#W}
      end

      {System.show ''}
      {System.show '*** GOLOG program example ***'}
      {ClearEverything}
      _ = {LoadToyWeather}
      {SetFluent observations S0 nil}
      {SetFluent states S0 ['Sunny' 'Rainy']}
      {SetFluent path S0 unit}
      Prog = {Seq [ {Prim {MakeAction observe ['walk']}}
                    {Prim {MakeAction observe ['shop']}}
                    {Prim {MakeAction observe ['clean']}}
                    {Prim {MakeAction run_viterbi []}} ]}
      Final = {ExecuteProg Prog S0 1000}
   in
      {System.show 'Final observations fluent:'
       #{Holds observations Final nil}}
      {System.show 'Situation depth:'#{SituationDepth Final}}
      {System.show ''}
      {System.show 'Artifact execution complete.'}
   end

   {Main}
end
