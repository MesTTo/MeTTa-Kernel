#!/bin/sh
# Purpose: prove the translator's per-symbol context markers are private to the
#   translation that set them, across a thread boundary and across nesting.
# Guarantees:
#   - a clause translation running while another THREAD sits inside a runnable
#     translation sees only its own `clause` context, so the two do not share
#     symbol_head/2 rows
#   - a runnable translation nested inside another removes only its own marker,
#     so the outer one still reads `runnable` afterwards
# Assumes:
#   - a probe rule is registered by asserting `translator_rule/2`, the dynamic
#     registry, with `[]` for "declared nothing". `translator_rule/1` is a
#     STATIC projection over it (`translator_rules.pl:173`), so the older
#     spelling here, `assertz(translator_rule(Name))`, stopped working the day
#     the registry grew its declarations argument and raised
#     "No permission to modify static procedure". Nothing caught that, because
#     this file ran only from .github/workflows/ci.yml, which gates pull
#     requests into main and so never sees branch work.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

swipl -q -g "consult('$ROOT/engine/main.pl'),message_queue_create(_,[alias(loader_context_probe)]),assertz(translator_rule(loader_pause_probe,[])),assertz((loader_pause_probe(Gs):-thread_send_message(loader_context_probe,entered),thread_get_message(loader_context_probe,continue),Gs=done)),thread_create(translate_runnable_expr([loader_pause_probe],_,_),Id,[]),thread_get_message(loader_context_probe,entered),retractall(symbol_head(loader_clause_symbol,_)),translate_clause([=,[loader_clause_function],[loader_clause_symbol,1]],_),findall(Context,symbol_head(loader_clause_symbol,Context),Contexts),thread_send_message(loader_context_probe,continue),thread_join(Id,_),(Contexts==[clause]->true;throw(error(shared_runnable_translation_context,Contexts))),halt"

# A nested runnable translation must remove only its own context marker.
swipl -q -g "consult('$ROOT/engine/main.pl'),assertz(translator_rule(nested_context_probe,[])),assertz((nested_context_probe(Gs):-translate_runnable_expr([nested_inner_symbol],_,_),translate_expr([nested_outer_symbol],Gs,_))),retractall(symbol_head(nested_outer_symbol,_)),translate_runnable_expr([nested_context_probe],_,_),findall(Context,symbol_head(nested_outer_symbol,Context),Contexts),(Contexts==[runnable]->true;throw(error(lost_outer_runnable_context,Contexts))),halt"

printf 'loader concurrency checks passed\n'
