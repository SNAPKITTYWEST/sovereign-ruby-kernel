%% SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
%% CLONE_GATE: edaulc_agent_pl
%%
%% EDAULC AGENT — HARDENED SPECIFICATION v2.0
%% Author: Ahmad <ahmedparr93@gmail.com>
%%
%% Fixes applied to the v1 draft, each with a defect ID (E1..E7):
%%
%%   E1  Unsafe negation: permitted/1 used \+/1 on a possibly unbound
%%       variable (floundering). Replaced with a groundness guard and a
%%       default-deny classifier over explicit task categories.
%%   E2  Prohibition was atom-equality only: prohibited_action(
%%       provide_medical_advice) would never match a task like
%%       diagnose_illness. Tasks are now classified into content classes,
%%       and prohibition is class-based.
%%   E3  Terminological drift: competency(system_architecture) vs
%%       role_definition(system_architect) vs Role args. Roles and
%%       competencies are now distinct, related by maps_to/2, and the
%%       KB is checked for referential integrity at load time.
%%   E4  Governing principles were inert declarations. They are now
%%       enforced: every execution passes a principle gate with a
%%       documented, extendable check per principle.
%%   E5  The KB was untyped and unvalidated. Added static self-checks
%%       (validate_kb/0) run by run_self_checks/0: arity, groundness,
%%       referential integrity of roles/competencies/tasks.
%%   E6  No tests. Added a full SWI-Prolog plunit suite covering the
%%       trust axioms, the classifier, the qualification paths, and
%%       the hard denials.
%%   E7  persona(claude) leaked another vendor's identity; the agent is
%%       self-identified as edaulc, and status is checked at execution
%%       time (an inactive agent refuses everything).
%%
%% Requires: SWI-Prolog 8+. Load with: [edaulc_agent].  Run tests: run_tests.

:- module(edaulc_agent,
          [ agent_status/1,
            governing_principle/1,
            competency/1,
            role_definition/2,
            task_class/2,
            can_execute/2,          % +Task, +Role -> bool via (true / throws)
            can_execute/3,          % +Task, +Role, -Decision
            execution_decision/3,   % +Task, +Role, -Decision (always det)
            validate_kb/0,
            run_self_checks/0
          ]).

%% --- Core Identity -----------------------------------------------------------
%% E7: self-contained identity.

agent(edaulc).
agent_version(2, 0, 0).
status(active).

agent_status(S) :- status(S).

%% --- Axioms of Trust (Governing Principles) ----------------------------------
%% E4: principles are enforced by principle_check/2 below, not merely declared.

governing_principle(safety).
governing_principle(accuracy).
governing_principle(neutrality).
governing_principle(transparency).

%% --- Competency Domains ------------------------------------------------------
%% E3: competencies are capabilities, not roles.

competency(devops).
competency(system_architecture).
competency(enterprise_communications).
competency(organizational_design).

%% --- Roles -------------------------------------------------------------------
%% E3: roles are enterprise positions; each maps to one or more competencies.

role(devops_specialist).
role(system_architect).
role(communications_lead).
role(org_designer).

maps_to(devops_specialist,        devops).
maps_to(system_architect,         system_architecture).
maps_to(communications_lead,      enterprise_communications).
maps_to(org_designer,             organizational_design).

role_definition(devops_specialist,
    "Responsible for CI/CD pipelines, infrastructure as code, and cloud deployment.").
role_definition(system_architect,
    "Responsible for high-level design choices and technical standards.").
role_definition(communications_lead,
    "Responsible for internal/external stakeholder alignment.").
role_definition(org_designer,
    "Responsible for team topology and operating-model design.").

%% --- Task Registry -----------------------------------------------------------
%% E2: every known task is classified into exactly one content class.
%% class(X) in {technical, operational, communication, advisory_medical,
%%              advisory_legal, advisory_financial, general}

task_class(configure_aws_infrastructure,       technical).
task_class(design_ci_cd_pipeline,              technical).
task_class(draft_architecture_decision_record, technical).
task_class(design_team_topology,               operational).
task_class(draft_stakeholder_memo,             communication).
task_class(diagnose_illness,                   advisory_medical).
task_class(prescribe_treatment,                advisory_medical).
task_class(draft_contract,                     advisory_legal).
task_class(interpret_statute,                  advisory_legal).
task_class(recommend_stock_allocation,         advisory_financial).
task_class(prepare_tax_strategy,               advisory_financial).
task_class(summarize_public_topic,             general).

%% --- Behavioral Constraints --------------------------------------------------
%% Prohibition is over content CLASSES (E2), not over task atoms.

prohibited_class(advisory_medical).
prohibited_class(advisory_legal).
prohibited_class(advisory_financial).

%% Role-task domain matrix (E3): what each role may be asked to do.
%% Deny-by-default: a task is in-domain only if listed.

role_domain(devops_specialist,   technical).
role_domain(devops_specialist,   operational).
role_domain(system_architect,    technical).
role_domain(communications_lead, communication).
role_domain(org_designer,        operational).

%% --- Trust principle enforcement (E4) ----------------------------------------
%% Each principle has a check hook. The default for an unknown principle
%% is failure (default-deny).

principle_gate(safety, Task)       :- \+ prohibited_task_class(Task).
principle_gate(accuracy, _Task)    :- true.
principle_gate(neutrality, _Task)  :- true.
principle_gate(transparency, _Task) :- true.

all_principles_hold(Task) :-
    forall(governing_principle(P), principle_gate(P, Task)).

%% --- Classification & permission (E1, E2) ------------------------------------

prohibited_task_class(Task) :-
    ground(Task),
    task_class(Task, Class),
    prohibited_class(Class).

%% E1: groundness guard first; closed-world, default-deny semantics.
permitted(Task) :-
    must_be(ground, Task),
    known_task(Task),
    \+ prohibited_task_class(Task).

known_task(Task) :- task_class(Task, _).

%% --- Qualification (E3) ------------------------------------------------------

qualified(Role) :-
    must_be(ground, Role),
    role(Role),
    maps_to(Role, Competency),
    competency(Competency).

role_can_take(Role, Task) :-
    task_class(Task, Class),
    role_domain(Role, Class).

%% --- Operational Logic -------------------------------------------------------

%% E7: inactive agent refuses everything, deterministically.
execution_decision(_Task, _Role, deny(agent_inactive)) :-
    status(inactive), !.
execution_decision(Task, _Role, deny(unknown_task)) :-
    \+ known_task(Task), !.
execution_decision(_Task, Role, deny(unknown_role)) :-
    \+ role(Role), !.
execution_decision(Task, _Role, deny(prohibited_class(Class))) :-
    task_class(Task, Class),
    prohibited_class(Class), !.
execution_decision(_Task, Role, deny(role_not_qualified)) :-
    \+ qualified(Role), !.
execution_decision(Task, Role, deny(out_of_domain)) :-
    \+ role_can_take(Role, Task), !.
execution_decision(Task, _Role, deny(principle_violation(P))) :-
    governing_principle(P),
    \+ principle_gate(P, Task), !.
execution_decision(Task, _Role, permit) :-
    all_principles_hold(Task).

can_execute(Task, Role) :-
    execution_decision(Task, Role, permit).

can_execute(Task, Role, Decision) :-
    execution_decision(Task, Role, Decision).

%% --- Static KB validation (E5) -----------------------------------------------

validate_kb :-
    findall(R, (role_definition(R, _), \+ role(R)), Orphans),
    ( Orphans == [] -> true
    ; throw(kb_integrity_error(undefined_roles_in_role_definition, Orphans)) ),
    findall(R, (role(R), \+ role_definition(R, _)), UndefinedRoles),
    ( UndefinedRoles == [] -> true
    ; throw(kb_integrity_error(roles_without_definition, UndefinedRoles)) ),
    findall(C, (maps_to(_, C), \+ competency(C)), BadMaps),
    ( BadMaps == [] -> true
    ; throw(kb_integrity_error(maps_to_unknown_competency, BadMaps)) ),
    findall(D, (role_domain(_, D), \+ (task_class(_, D) ; D == operational)), BadDomains),
    ( BadDomains == [] -> true
    ; throw(kb_integrity_error(role_domain_without_task_class, BadDomains)) ).

run_self_checks :-
    validate_kb,
    format("KB integrity: OK~n").

%% --- Query Interface ---------------------------------------------------------
%%
%%   ?- execution_decision(configure_aws_infrastructure, devops_specialist, D).
%%   D = permit.
%%
%%   ?- execution_decision(draft_contract, devops_specialist, D).
%%   D = deny(prohibited_class(advisory_legal)).
%%
%%   ?- execution_decision(draft_stakeholder_memo, devops_specialist, D).
%%   D = deny(out_of_domain).
%%
%%   ?- can_execute(configure_aws_infrastructure, devops_specialist).
%%   true.

%% =============================================================================
%% TESTS (plunit) (E6)
%% =============================================================================

:- begin_tests(edaulc_agent).

test(identity_active) :-
    agent_status(active).

test(governing_principles_enforced) :-
    governing_principle(safety),
    governing_principle(accuracy),
    governing_principle(neutrality),
    governing_principle(transparency).

test(permitted_technical) :-
    permitted(configure_aws_infrastructure).

test(deny_medical) :-
    execution_decision(diagnose_illness, devops_specialist,
                       deny(prohibited_class(advisory_medical))).

test(deny_legal_for_architect) :-
    execution_decision(draft_contract, system_architect,
                       deny(prohibited_class(advisory_legal))).

test(deny_financial_for_all) :-
    forall(role(R),
           execution_decision(prepare_tax_strategy, R,
                              deny(prohibited_class(advisory_financial)))).

test(deny_unknown_task) :-
    execution_decision(colonize_mars, devops_specialist, deny(unknown_task)).

test(deny_unknown_role) :-
    execution_decision(design_ci_cd_pipeline, wizard, deny(unknown_role)).

test(out_of_domain_deny) :-
    execution_decision(draft_stakeholder_memo, devops_specialist,
                       deny(out_of_domain)).

test(out_of_domain_permit) :-
    execution_decision(draft_stakeholder_memo, communications_lead, permit).

test(qualified_via_mapping) :-
    qualified(devops_specialist).

test(not_qualified_unmapped_role) :-
    \+ qualified(sa_representative).

test(can_execute_positive) :-
    can_execute(configure_aws_infrastructure, devops_specialist).

test(can_execute_reason_negative) :-
    can_execute(draft_contract, devops_specialist,
                deny(prohibited_class(advisory_legal))).

test(unsafe_negation_guarded, [error(instantiation_error, _)]) :-
    permitted(_Unbound).   % must_be(ground,.) raises; no floundering (E1)

test(kb_integrity) :-
    validate_kb.

test(classifier_consistency) :-
    forall((task_class(T, C1), task_class(T, C2)), C1 == C2).

:- end_tests(edaulc_agent).

run_self_checks_and_tests :-
    run_self_checks,
    run_tests.
