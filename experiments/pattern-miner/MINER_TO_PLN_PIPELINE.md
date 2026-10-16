# Pattern Miner to PLN Integration

## Abstract

This document describes the implemented connection between the MeTTa frequent pattern miner and the Probabilistic Logic Networks (PLN) reasoner. The miner discovers patterns in a knowledge base and reports each pattern with a support count. The integration layer converts those results into PLN sentences with simple truth values (STVs), records mined binary conjunctions as conditional implications, and makes the resulting beliefs available to PLN inference and query operations.

The integration test uses the `ugly_man_sodaDrinker.metta` dataset. Starting from the unary seed `(Inheritance $person ugly)`, it discovers shared properties such as `human`, `man`, `woman`, and `sodaDrinker`. A mined rule can then be applied to a separately evidenced premise, or queried using `PLN.Query`.

## Pipeline overview

```text
Input knowledge base
        │
        ▼
Frequent pattern miner
  seed + minsup + depth
        │
        ├── unary patterns and support counts
        └── discovered conjunctions and support counts
                    │
                    ▼
          Miner–PLN bridge
        ├── pattern → PLN Sentence with STV
        └── binary conjunction → conditional Implication with STV
                    │
                    ▼
               &pln-beliefs
        ├── PLN Modus Ponens → derived beliefs
        ├── PLN.Derive → expanded belief state
        └── PLN.Query → best-confidence query answer
```

The checked-in `experiments/pattern-miner/pattern-miner.metta` remains the standalone miner. The optional `experiments/pattern-miner/miner-pln-integration.metta` wrapper obtains support results and hands them to `miner-pln-bridge.metta`, which creates the PLN sentences and rules. The ordinary miner can therefore be imported and run without PLN.

The entry points fetch the PLN library from `https://github.com/trueagi-io/PLN.git` with PeTTa's `git-import!`, then load it with `(import! &self (library PLN lib_pln))`. The checkout is cached under the ignored `hyperon-miner/repos/PLN` directory and is not part of the miner's tracked source. The first run therefore requires GitHub access; later runs reuse the cached checkout.

## Why connect the miner to PLN?

The miner and PLN answer different questions, so connecting them lets the system use both kinds of information:

- **The miner answers an empirical question:** “How many matches of this pattern are in this database?” It produces a pattern and its support count.
- **PLN answers a reasoning question:** “Given these beliefs, their truth values, and the available inference rules, what else can be concluded?” It represents beliefs as `Sentence` atoms with truth values and evidence, then applies inference rules such as Modus Ponens.
- **The bridge connects those answers:** it turns a miner result such as `(supportOf $pattern $count)` into a PLN sentence, and turns eligible binary conjunctions into conditional implications. That allows PLN to reason with mined results and other beliefs.

For example, suppose mining finds that 5 database subjects have both `ugly` and `sodaDrinker`. The miner reports the conjunction and support; it does not itself conclude what follows from that pattern. The bridge can represent the co-occurrence as conditional rules with truth values, and PLN can combine a rule such as `ugly → sodaDrinker` with a separately evidenced premise that a particular subject is ugly. The derived conclusion is a PLN result, while the original support remains a count from the dataset.

This separation is useful because a frequent pattern and a logical consequence are not the same thing. A high support count says that a pattern occurs often in the selected data. It does not, by itself, say that the pattern is universally true, that one part causes another, or that the pattern is already known. PLN adds a representation for uncertain beliefs and a way to perform inference; its output depends on the STV calculations, evidence, rules, and query settings supplied to it.

The integration therefore provides a path from **observed structure** to **beliefs PLN can use**. It does not mean PLN automatically decides which patterns are meaningful, suppresses every obvious pattern, or guides every candidate the miner considers.

## Why is the bridge at the pattern-miner boundary?

The optional integration wrapper is the handoff point: it receives completed miner results, then passes those results to the bridge. At that point each result has a pattern shape and a support count, which are the inputs the bridge needs to construct the corresponding PLN belief and provenance record.

Keeping the conversion here also preserves a clear responsibility boundary:

1. **Candidate generation and support counting** stay in `experiments/frequent-pattern-miner/`. This code proposes structural patterns and checks them against the database.
2. **Standalone miner orchestration** stays in `experiments/pattern-miner/pattern-miner.metta`. It runs mining and optional surprisingness scoring without importing PLN.
3. **Optional PLN pipeline orchestration** stays in `experiments/pattern-miner/miner-pln-integration.metta`. It obtains support records, discovers seeded shared-property conjunctions for the integration test, and calls the bridge.
4. **PLN representation and handoff** stay in `experiments/pattern-miner/miner-pln-bridge.metta`. It computes the configured STVs, creates `Sentence` and `Implication` atoms, and exposes the results to PLN.
5. **Logical inference** stays in the imported PLN implementation under `repos/PLN/`. It consumes beliefs and applies PLN rules; the miner does not reimplement those rules.

This location is a design choice, not a claim that PLN could never be used elsewhere. Putting a PLN call inside candidate generation or support counting would create a tighter, bidirectional coupling: each candidate might trigger reasoning before its data support is known, and the mining result could depend on which PLN rules, beliefs, or inference-step limit happen to be loaded. In particular, **PLN returning no derivation is not proof that a candidate is false or absent from the data**. It can mean only that the current beliefs and rules did not produce a proof within the configured search. Treating “no derivation” as a rejection could remove a real, frequent pattern that PLN simply does not know how to derive.

There is also a cost tradeoff. Candidate expansion can produce many structures, and PLN derivation can itself search over beliefs and rules. Running it for every candidate may add substantial work before the miner has even counted those candidates. The current output-boundary design avoids making each support check depend on a PLN search and lets the miner remain responsible for the empirical frequency result.

An earlier PLN filter could still be appropriate for a narrowly defined purpose—for example, pruning a candidate only when PLN proves that it violates an explicit disjointness or type constraint. Such a filter needs a three-way interpretation: **proven contradiction** may prune; **proven compatible** may continue; **no derivation / unknown** must continue to ordinary mining. It should be evaluated separately for correctness and runtime savings. That constraint-checking loop is not what the current miner-to-PLN bridge implements.

## Mining and conjunction discovery

The standalone miner receives a database, an initial pattern, minimum support, depth, and a conjunction-expansion flag. The optional PLN wrapper adds shared-property discovery for a depth-zero `Inheritance` seed:

1. Mines the unary seed through the frequent-pattern miner.
2. Finds other properties attached to subjects that have the seed property.
3. Constructs candidate binary conjunctions sharing the same subject variable.
4. Counts each candidate against the original database and retains candidates meeting `minsup`.
5. Returns a list of `(supportOf $pattern $count)` records.

For this dataset, the file contains 60 ground facts: 20 `human`, 10 `man`, 10 `woman`, 10 `ugly`, and 10 `sodaDrinker` facts. The test starts with the seed `(Inheritance $person ugly)` and `minsup = 5`. It checks that the miner discovers, among others:

```metta
(supportOf (Inheritance $_0 ugly) 10)
(supportOf (, (Inheritance $_1 ugly) (Inheritance $_1 human)) 10)
(supportOf (, (Inheritance $_2 ugly) (Inheritance $_2 man)) 5)
(supportOf (, (Inheritance $_3 ugly) (Inheritance $_3 woman)) 5)
(supportOf (, (Inheritance $_4 ugly) (Inheritance $_4 sodaDrinker)) 5)
```

The conjunctions are discovered from shared subjects, not manually entered as initial patterns in the integration test.

## Miner-to-PLN conversion

Each support record becomes a PLN `Sentence`, carrying the pattern, an STV, and a provenance stamp. A typical mined-pattern sentence has this form:

```metta
(Sentence
    ((Inheritance $_0 ugly) (stv $strength $confidence))
    ((MinerPatternEvidence PatternMinerDataset
                           (Inheritance $_0 ugly)
                           10)))
```

For every pattern shape, the bridge uses the total number of atoms in the
database as the strength denominator. It calculates the mined-pattern STV as:

```text
strength   = support / total-database-atoms
confidence = support / (support + 1)
```

For the 60-fact example, the unary `ugly` pattern has strength `10 / 60 ≈
0.1667`. The conjunction `ugly ∧ human` has strength `10 / 60 ≈ 0.1667` as
well. These strengths express each pattern's frequency relative to the full
database content; they are not entity-level probabilities.

For each mined binary conjunction, the bridge creates both conditional directions. Given a conjunction with joint support `n(A ∧ B)`, it calculates each direction as:

```text
strength(A → B)   = support(A ∧ B) / support(A)
confidence(A → B) = support(A) / (support(A) + 1)
```

For example, the conjunction `ugly ∧ sodaDrinker` has support 5. Since there are 10 ugly subjects and 10 soda-drinker subjects, the bridge emits:

```text
ugly → sodaDrinker: strength = 5/10 = 0.5, confidence = 10/11 ≈ 0.9091
sodaDrinker → ugly: strength = 5/10 = 0.5, confidence = 10/11 ≈ 0.9091
```

For `ugly ∧ human`, support is 10, while `human` support is 20, so the two directions have different STVs:

```text
ugly → human: strength = 10/10 = 1.0, confidence = 10/11 ≈ 0.9091
human → ugly: strength = 10/20 = 0.5, confidence = 20/21 ≈ 0.9524
```

These implication calculations express a conditional frequency and an antecedent-support heuristic. The confidence expression with `k = 1` is the current bridge's chosen estimate; it is not a PLN inference formula derived from a statistical confidence interval.

## Inference and query

The test adds an independently evidenced premise, for example:

```metta
(Sentence ((Inheritance Alaura ugly) (stv 1.0 1.0))
          ((ExternalQuery Alaura)))
```

It then applies the mined rule `ugly → sodaDrinker`. PLN's Modus Ponens combines the premise and rule STVs. The PLN library is loaded through `(library PLN lib_pln)`; its implemented Modus Ponens formula is:

```text
result strength   = premise strength × rule strength
                    + 0.02 × (1 − premise strength)
result confidence = premise strength × rule strength
                    × premise confidence × rule confidence
```

With premise STV `(1.0, 1.0)` and the mined `ugly → sodaDrinker` STV `(0.5, 0.9091)`, this yields approximately `(0.5, 0.4545)` for the direct one-step result.

The bridge also exposes `pln-query-from-beliefs`. It converts the belief space into a list and calls `PLN.Query` with a step bound. `PLN.Query` runs PLN derivation and returns the highest-confidence answer it finds for the requested term, along with evidence; it returns an empty result if no matching answer is found. A query result can include additional derivation or revision steps, so its STV may differ from the direct one-step Modus Ponens value. Interpret the answer together with its evidence stamp and inference path, rather than as the original mined rule's STV.

## Verification

The integration test is `experiments/pattern-miner/tests/test_pln_wired_pipeline.metta`. Its mined-rule test checks that:

- the miner discovers `ugly ∧ human`, `ugly ∧ man`, `ugly ∧ woman`, and `ugly ∧ sodaDrinker` from the dataset;
- the bridge stores corresponding PLN implications in `&pln-beliefs`;
- unary patterns, conjunctions, and a non-`Inheritance` pattern all use the total database atom count as the denominator;
- PLN Modus Ponens derives conclusions from separately evidenced premises;
- the `pln-query-from-beliefs` wrapper returns a non-empty answer for a mined-rule query;
- a direct `PLN.Derive` call combines a fresh premise with the mined `ugly → human` rule and returns `Alaura human` in its expanded belief state.

Run it from the repository with:

```bash
PYTHONPATH=/home/eyorica/PeTTa/python python3 -c '
import os, sys
os.chdir("/home/eyorica/Downloads/pattern-miner-mm2/hyperon-miner/experiments/pattern-miner/tests")
from petta.cli import main
sys.argv = ["petta", "test_pln_wired_pipeline.metta"]
main()
'
```

The query tests check that a result is returned, without asserting a particular STV for PLN.Query's best answer because PLN may explore multiple derivations and choose or revise among them. The direct `PLN.Derive` test selects the mined `ugly → human` rule, combines it with a separately evidenced `Alaura ugly` premise, and checks that `Alaura human` appears in the returned belief state.

## Scope and limitations

- The integration test checks mined conjunction discovery, bridge conversion, total-database-content strength for multiple pattern shapes, Modus Ponens, a bounded PLN query, and direct `PLN.Derive` using a mined rule. It does not establish that every PLN inference mode is covered.

## Source files

- `experiments/pattern-miner/pattern-miner.metta` — checked-in standalone miner orchestration and surprisingness scoring.
- `experiments/pattern-miner/miner-pln-integration.metta` — optional wrapper connecting miner output to PLN and discovering seeded shared-property conjunctions.
- `experiments/pattern-miner/miner-pln-bridge.metta` — STV calculations, PLN sentence construction, conditional rule creation, Modus Ponens helpers, and query wrapper.
- `experiments/pattern-miner/tests/test_pln_wired_pipeline.metta` — end-to-end integration checks.
- `experiments/data/ugly_man_sodaDrinker.metta` — example dataset.
- `(library PLN lib_pln)` — the imported PLN package containing inference formulas and `PLN.Query`.
