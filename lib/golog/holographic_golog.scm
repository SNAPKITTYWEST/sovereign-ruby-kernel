;; SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
;; CLONE_GATE: holographic_golog_scm
;;
;; HOLOGRAPHIC μKANREN GOLOG ENGINE
;; Pure relational core — zero host imports, zero Python, zero bash
;; Hand-written μKanren + relational situation calculus
;; Author: Ahmad <ahmedparr93@gmail.com>

;; ============================================================================
;; 0. μKANREN PRIMITIVES (pure, host-free presentation)
;; ============================================================================

;; A substitution is an association list of (var . term)
;; The empty substitution is '()

;; walk : term × subst → term
(define (walk u s)
  (let ((pr (assv u s)))
    (if pr (walk (cdr pr) s) u)))

;; occurs? : var × term × subst → bool
(define (occurs? x v s)
  (let ((v (walk v s)))
    (cond
      ((var? v) (eqv? x v))
      ((pair? v) (or (occurs? x (car v) s)
                     (occurs? x (cdr v) s)))
      (else #f))))

;; ext-s : var × term × subst → subst | #f
(define (ext-s x v s)
  (if (occurs? x v s) #f `((,x . ,v) . ,s)))

;; unify : term × term × subst → subst | #f
(define (unify u v s)
  (let ((u (walk u s)) (v (walk v s)))
    (cond
      ((eqv? u v) s)
      ((var? u) (ext-s u v s))
      ((var? v) (ext-s v u s))
      ((and (pair? u) (pair? v))
       (let ((s (unify (car u) (car v) s)))
         (and s (unify (cdr u) (cdr v) s))))
      (else #f))))

;; mzero : empty stream
(define mzero '())

;; unit : state → stream
(define (unit s) (cons s mzero))

;; == : term × term → goal
(define (== u v)
  (lambda (s)
    (let ((s (unify u v s)))
      (if s (unit s) mzero))))

;; conj2 / disj2 (binary building blocks)
(define (conj2 g1 g2)
  (lambda (s)
    (bind (g1 s) g2)))

(define (disj2 g1 g2)
  (lambda (s)
    (mplus (g1 s) (g2 s))))

;; mplus / bind (stream interleaving)
(define (mplus $1 $2)
  (cond
    ((null? $1) $2)
    ((procedure? $1) (lambda () (mplus $2 ($1))))
    (else (cons (car $1) (mplus (cdr $1) $2)))))

(define (bind $ g)
  (cond
    ((null? $) mzero)
    ((procedure? $) (lambda () (bind ($) g)))
    (else (mplus (g (car $)) (bind (cdr $) g)))))

;; ============================================================================
;; 1. SITUATION TERMS (pure relational constructors)
;; ============================================================================

;; s0 is the constant initial situation
;; (do a s) is the successor situation

(define (s0o s) (== s 's0))

(define (doo a s s2)
  (== s2 `(do ,a ,s)))

(define (action-ofo s a)
  (fresh (s1)
    (== s `(do ,a ,s1))))

(define (prioro s s1)
  (fresh (a)
    (== s `(do ,a ,s1))))

(define (situation-deptho s n)
  (conde
    ((s0o s) (== n 0))
    ((fresh (a s1 m)
       (doo a s1 s)
       (situation-deptho s1 m)
       (pluso m 1 n)))))

;; ============================================================================
;; 2. RELATIONAL NATURAL NUMBERS (Peano)
;; ============================================================================

(define (zeroo n) (== n 'z))

(define (succo n n*)
  (== n* `(s ,n)))

(define (pluso n m k)
  (conde
    ((zeroo n) (== m k))
    ((fresh (n1 k1)
       (succo n1 n)
       (succo k1 k)
       (pluso n1 m k1)))))

;; ============================================================================
;; 3. HOLOGRAPHIC FLUENTS (relational successor-state axioms)
;; ============================================================================

;; holdingo : situation × value → goal
;; The holding fluent is a pure function of the situation term.

(define (holdingo s v)
  (conde
    ;; initial
    ((s0o s) (== v 'none))
    ;; successor
    ((fresh (a s1)
       (doo a s1 s)
       (conde
         ;; pickup(x) → holding = x
         ((fresh (x)
            (== a `(pickup ,x))
            (== v x)))
         ;; unstack(x,y) → holding = x
         ((fresh (x y)
            (== a `(unstack ,x ,y))
            (== v x)))
         ;; putdown(x) → holding = none
         ((fresh (x)
            (== a `(putdown ,x))
            (== v 'none)))
         ;; stack(x,y) → holding = none
         ((fresh (x y)
            (== a `(stack ,x ,y))
            (== v 'none)))
         ;; frame: any other action preserves previous value
         ((fresh (v1)
            (holdingo s1 v1)
            (== v v1)
            (conda
              ((fresh (x) (== a `(pickup ,x))) fail)
              ((fresh (x y) (== a `(unstack ,x ,y))) fail)
              ((fresh (x) (== a `(putdown ,x))) fail)
              ((fresh (x y) (== a `(stack ,x ,y))) fail)
              (succeed))))))))

;; ono : block × support × situation → goal
(define (ono x y s)
  (conde
    ;; initial: every block starts on table
    ((s0o s)
     (conde
       ((== y 'table) (blocko x))
       (fail)))
    ;; successor
    ((fresh (a s1)
       (doo a s1 s)
       (conde
         ;; putdown(x) makes on(x,table)
         ((== a `(putdown ,x)) (== y 'table))
         ;; stack(x,y) makes on(x,y)
         ((== a `(stack ,x ,y)))
         ;; pickup(x) or unstack(x,_) removes on(x,_)
         ((fresh (z)
            (== a `(pickup ,x))
            fail))
         ((fresh (z)
            (== a `(unstack ,x ,z))
            fail))
         ;; frame
         ((ono x y s1)
          (conda
            ((== a `(putdown ,x)) fail)
            ((== a `(stack ,x ,y)) fail)
            ((fresh (z) (== a `(pickup ,x))) fail)
            ((fresh (z) (== a `(unstack ,x ,z))) fail)
            (succeed))))))))

;; clearo : block × situation → goal
(define (clearo x s)
  (conde
    ((s0o s) (blocko x))
    ((fresh (a s1)
       (doo a s1 s)
       (conde
         ;; after pickup or unstack of something on x, x becomes clear
         ((fresh (y)
            (conde
              ((== a `(pickup ,y)))
              ((== a `(unstack ,y ,x))))
            (clearo x s1)))
         ;; stack onto x makes x not clear
         ((fresh (y)
            (== a `(stack ,y ,x))
            fail))
         ;; frame
         ((clearo x s1)
          (conda
            ((fresh (y) (== a `(stack ,y ,x))) fail)
            (succeed))))))))

;; ============================================================================
;; 4. PRECONDITION AXIOMS (Poss)
;; ============================================================================

(define (posso a s)
  (conde
    ;; pickup(x)
    ((fresh (x)
       (== a `(pickup ,x))
       (clearo x s)
       (ono x 'table s)
       (holdingo s 'none)))
    ;; putdown(x)
    ((fresh (x)
       (== a `(putdown ,x))
       (holdingo s x)))
    ;; stack(x,y)
    ((fresh (x y)
       (== a `(stack ,x ,y))
       (holdingo s x)
       (clearo y s)
       (=/= y 'table)))
    ;; unstack(x,y)
    ((fresh (x y)
       (== a `(unstack ,x ,y))
       (ono x y s)
       (clearo x s)
       (holdingo s 'none)
       (=/= y 'table)))))

;; ============================================================================
;; 5. GOLOG PROGRAM RELATIONS
;; ============================================================================

;; Programs are relational terms:
;; (prim a), (seq p1 p2), (choice p1 p2), (star p),
;; (test g), (if g p1 p2), (while g p), (prio p1 p2)

;; transo : program × situation × program* × situation* → goal
(define (transo p s p* s*)
  (conde
    ;; primitive
    ((fresh (a)
       (== p `(prim ,a))
       (posso a s)
       (doo a s s*)
       (== p* 'nil)))
    ;; sequence
    ((fresh (p1 p2 p1*)
       (== p `(seq ,p1 ,p2))
       (conde
         ((transo p1 s p1* s*)
          (conde
            ((== p1* 'nil) (== p* p2))
            ((=/= p1* 'nil) (== p* `(seq ,p1* ,p2)))))
         ((finalo p1 s)
          (transo p2 s p* s*)))))
    ;; choice
    ((fresh (p1 p2)
       (== p `(choice ,p1 ,p2))
       (conde
         ((transo p1 s p* s*))
         ((transo p2 s p* s*)))))
    ;; star
    ((fresh (q)
       (== p `(star ,q))
       (fresh (q*)
         (transo q s q* s*)
         (conde
           ((== q* 'nil) (== p* `(star ,q)))
           ((=/= q* 'nil) (== p* `(seq ,q* (star ,q))))))))
    ;; test
    ((fresh (g)
       (== p `(test ,g))
       (call g s)
       (== p* 'nil)
       (== s* s)))
    ;; if
    ((fresh (g pt pe)
       (== p `(if ,g ,pt ,pe))
       (conde
         ((call g s) (transo pt s p* s*))
         ((noto (lambda (s0) (call g s0)) s) (transo pe s p* s*)))))
    ;; while
    ((fresh (g q)
       (== p `(while ,g ,q))
       (conde
         ((call g s) (transo `(seq ,q (while ,g ,q)) s p* s*))
         ((noto (lambda (s0) (call g s0)) s) (== p* 'nil) (== s* s)))))
    ;; prioritised choice
    ((fresh (p1 p2)
       (== p `(prio ,p1 ,p2))
       (conde
         ((transo p1 s p* s*))
         ((noto (lambda (s0) (fresh (r t) (transo p1 s0 r t))) s)
          (transo p2 s p* s*)))))))

;; finalo : program × situation → goal
(define (finalo p s)
  (conde
    ((== p 'nil))
    ((fresh (p1 p2)
       (== p `(seq ,p1 ,p2))
       (finalo p1 s)
       (finalo p2 s)))
    ((fresh (p1 p2)
       (== p `(choice ,p1 ,p2))
       (conde ((finalo p1 s)) ((finalo p2 s)))))
    ((fresh (q) (== p `(star ,q))))
    ((fresh (g)
       (== p `(test ,g))
       (call g s)))
    ((fresh (g pt pe)
       (== p `(if ,g ,pt ,pe))
       (conde
         ((call g s) (finalo pt s))
         ((noto (lambda (s0) (call g s0)) s) (finalo pe s)))))
    ((fresh (g q)
       (== p `(while ,g ,q))
       (noto (lambda (s0) (call g s0)) s)))
    ((fresh (p1 p2)
       (== p `(prio ,p1 ,p2))
       (conde ((finalo p1 s)) ((finalo p2 s)))))))

;; ============================================================================
;; 6. EXECUTION (search for a terminating trace)
;; ============================================================================

(define (executo p s s-final)
  (conde
    ((finalo p s) (== s s-final))
    ((fresh (p* s*)
       (transo p s p* s*)
       (executo p* s* s-final)))))

;; ============================================================================
;; 7. AUXILIARY RELATIONS
;; ============================================================================

(define (blocko x)
  (conde
    ((== x 'A))
    ((== x 'B))
    ((== x 'C))))

(define (noto g s)
  (lambda (subst)
    (if (null? (g s)) (unit subst) mzero)))

;; var? — check if term is an unbound logic variable (host-specific)
;; In a real Scheme μKanren this would be (define (var? x) (vector? x))
;; Here we approximate for documentation purposes
(define (var? x) (symbol? x))

;; ============================================================================
;; 8. EXAMPLE QUERIES (hand-written relational goals)
;; ============================================================================

;; Query 1: after pickup(A) the robot is holding A
;; (run 1 (q)
;;   (fresh (s1)
;;     (doo '(pickup A) 's0 s1)
;;     (holdingo s1 q)))
;; Expected: (A)

;; Query 2: legal sequence that ends with robot holding nothing, A on table
;; (run 1 (s-final)
;;   (executo '(seq (prim (pickup A)) (prim (putdown A))) 's0 s-final))

;; Query 3: find any situation in which holding is A
;; (run 5 (s)
;;   (holdingo s 'A))

;; Query 4: GOLOG while-loop that keeps picking up and putting down A
;; (run 1 (s)
;;   (executo '(star (seq (prim (pickup A)) (prim (putdown A)))) 's0 s))

;; ============================================================================
;; 9. HOLOGRAPHIC INVARIANTS (relational statements of correctness)
;; ============================================================================

;; H1: Every fluent value is a pure function of the situation term.
;;     (∀ s v)(holdingo s v) is decided solely by the action history of s.
;;
;; H2: Poss is evaluated only against fluents of the current situation.
;;     (∀ a s)(posso a s) ⇔ conditions on (holdingo s ·), (ono · · s), …
;;
;; H3: Trans never produces a successor situation unless Poss holds.
;;     (∀ p s p* s*)(transo p s p* s*) ∧ (p = (prim a)) ⇒ (posso a s)
;;
;; H4: Final programs may terminate; non-final programs must step or block.
;;
;; H5: The empty program 'nil is always final.
;;
;; H6: Star is always final (zero iterations) and may also unfold.
;;
;; H7: The whole engine is a pure relation; no mutable store exists.
;;     All state is encoded in the situation term.

;; ============================================================================
;; END OF PURE μKANREN HOLOGRAPHIC GOLOG
;; No Python, no imports, no host runtime, no bash.
;; Only relational goals, unification, and interleaving streams.
;; ============================================================================
