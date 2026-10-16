# Why Integrate PLN with Hyperon Pattern Miner?

## 1. The Problem with Pure Statistical Mining

The Hyperon frequent-pattern miner (`frequent-pattern-miner/`) discovers patterns purely by counting — it finds structures that appear frequently in the AtomSpace. This produces correct statistical answers but has three concrete limitations that PLN directly addresses.

### Limitation 1: Redundant beliefs accumulate across mining runs

Within a single mining run, the miner already handles deduplication: `unique-atom` removes duplicate patterns and `sort_conj` canonicalises conjunction ordering so `(, A B)` and `(, B A)` are treated as the same pattern.

The problem PLN addresses is different: **across multiple runs**. When a second mining run on new or extended data finds `ugly → human` again, the miner has no mechanism to recognise that this rule already exists in the belief space from the first run. Without PLN, the rule is simply added again. With PLN, `Truth_Revision` merges the two observations using their evidence stamps. If the stamps overlap (same dataset), `StampDisjoint` detects it and skips the redundant revision. If the stamps are genuinely different (different data subsets), the confidence updates correctly.

**This only matters in iterative or incremental mining setups, not in a single one-shot run.**

### Limitation 2: PLN derives facts the miner cannot find directly

This applies in a specific scenario: when a relationship exists between two concepts but those concepts do not directly co-occur in the dataset.

The miner found:

```metta
ugly → man (from co-occurrence in the data)
man → sportsFan (from an external domain rule, not in the dataset)
```

If `ugly∧sportsFan` does not appear in the database, the miner cannot find it. PLN's Deduction rule computes the chain:

```
Truth_Deduction(ugly→man, man→sportsFan) → ugly→sportsFan
```

This is only meaningful when the derived fact is **absent from the data**. If `ugly∧sportsFan` co-occurs in the dataset, the miner finds it directly with higher precision, and PLN's deduction adds nothing beyond what counting already provides. The value of PLN here is for **out-of-distribution inference** — extending knowledge beyond what the dataset directly contains.

### Limitation 3: Mined rules + domain axioms = new conclusions

Mined rules are empirical (from data). Domain axioms are logical (from knowledge). PLN composes them:

```
Mined:   ugly → man         (support=5, PLN stv(0.5, 0.909))
Axiom:   man → adult        (external knowledge, stv(1.0, 0.9))
Derived: ugly → adult       (PLN Deduction, never directly mined)
```

Pure counting cannot cross the boundary between empirical patterns and external logical knowledge. PLN can.

---

## 2. Why Integrate at the pattern-miner/ Layer Specifically?

The project has multiple layers where PLN could have been integrated. Each was considered for concrete reasons.

### Option A: Inside frequent-pattern-miner/ — partially appropriate

The `frequent-pattern-miner/` modules handle raw pattern generation and support counting. Not all of them are equally appropriate for PLN integration.

**`candidate.metta` and `build-specialization.metta`** — PLN adds no value here. These generate single-atom patterns like `(Inheritance $x ugly)`. A single Atomese link has no logical structure to contradict. PLN has no basis for pruning or scoring at this stage because no conjunction exists yet.

**`conjunction-expansion.metta`** — PLN integration IS appropriate, but the benefit is conditional. This is the expensive step. The function `checker()` at line 117 runs `sup-eval` (a full database scan) on every candidate conjunction before deciding whether to keep it. At depth=1 with 5 properties, this generates hundreds of candidates, each requiring a database scan.

PLN can act as a prefilter inside `checker()` for one specific case: when `&pln-beliefs` already contains an explicit contradiction for a candidate conjunction. For example, if PLN knows:

```metta
(Implication (Inheritance $x man) (Not (Inheritance $x woman)))
```

then any conjunction `(, man woman)` is discarded before `sup-eval` runs.

**Important limitation:** When PLN has no belief about a candidate (which is the case for most candidates and always on the first mining run), `sup-eval` still runs. The precheck only saves work in proportion to how many contradiction beliefs `&pln-beliefs` already contains. On a cold start with an empty belief space, the precheck adds a small overhead with zero benefit. The value accumulates across iterative mining runs as the belief space grows.

**The integration point:**

```metta
(= (checker $db $pattern $ms)
    (let*
    (
        ($conjuncts  (get-conjuncts $pattern))
        ($flat       (cons-atom , $conjuncts))
        ;; PLN precheck — only skips sup-eval when a contradiction is found
        ($pln-ok     (pln-conjunction-feasible? &pln-beliefs $flat))
        ($result     (if $pln-ok (sup-eval $db $flat $ms) False))
        ($final      (if $result $pattern ()))
    )
   $final
    )
)
```

When `&pln-beliefs` is empty or has no relevant belief, `pln-ok` returns `True` and `sup-eval` runs as before — behaviour is identical to the original miner.

### Option B: Inside surprisingness/

The `surprisingness/` module (`isurp.metta`, `jsd.metta`, `IIsurp-old.metta`) scores patterns for novelty using a statistical independence baseline:

```
Expected(A ∧ B) = P(A) × P(B)     ← independence assumption
Surprisingness  = P(A ∧ B)_observed − P(A) × P(B)
```

**What PLN can contribute here — and what it cannot:**

PLN could in principle replace the independence baseline with a belief-derived prior: instead of assuming A and B are unrelated, ask PLN what it expects P(A∧B) to be given existing rules.

However, this only works under one specific condition: PLN must already have a direct rule predicting that exact conjunction. For the three-way candidate `(, ugly man sodaDrinker)`, PLN would need a rule like:

```metta
(Implication (, (Inheritance $x ugly) (Inheritance $x man))
             (Inheritance $x sodaDrinker))
```

The two separate rules `ugly → man` (strength=0.5) and `ugly → sodaDrinker` (strength=0.5) are **not sufficient**. They share an antecedent rather than forming a chain, so PLN deduction does not apply. More importantly, they say nothing about whether the same five ugly people are both men and soda drinkers. With those two rules alone, PLN cannot estimate the three-way overlap.

**Critically, PLN cannot reduce the counting cost here.** The miner must generate the candidate and run `sup-eval` before a PLN comparison is possible. Using a PLN prior score to filter results afterward can reduce what gets promoted to `&pln-beliefs`, but it does not save any mining computation.

**The three outcomes when PLN is consulted after counting:**

1. PLN has a direct matching rule → use it as the baseline, compare to observed
2. PLN can derive an equivalent prediction → compare the derived estimate
3. PLN has insufficient knowledge → treat the estimate as unknown; do not interpret silence as "already explained"; fall back to the statistical score

**Current state:** The surprisingness module uses the statistical independence baseline. A PLN-prior comparison for output filtering is a possible addition in iterative mining but is not implemented and would require PLN to have direct rules for each candidate — a condition rarely met on early iterations.

### Option C: Inside truth-values/ (rejected)

The `truth-values/` module (`est-tv.metta`, `emp-tv.metta`) computes empirical and estimated truth values for patterns from raw data. This is where strength/confidence numbers are produced before the miner reports results.

PLN was not integrated here because these functions compute values from raw database matches — they are data-driven, not inference-driven. PLN operates on derived beliefs, not raw database queries. Mixing PLN into the TV computation layer would confuse two distinct epistemic sources:

- `emp-tv`: what the data directly shows (empirical)
- `PLN-derived`: what can be inferred from other beliefs (rational)

These should remain separate and be combined only at the output stage via `Truth_Revision`, which is exactly what `miner-pln-bridge.metta` does.

### Option D: Standalone PLN layer — the pattern-miner/ bridge (chosen)

`pattern-miner/` sits above `frequent-pattern-miner/` in the architecture. It is the orchestrator: it calls the frequent-pattern-miner, collects results, applies surprisingness scoring, and outputs to `&kb`.

**This is the correct integration point because:**

1. **It has access to the complete mined output.** By the time `pattern-miner.metta` runs its post-mining step, all `supportOf` atoms are collected. PLN needs complete pattern lists to compute meaningful beliefs — not partial results from inside the mining loop.

2. **It is the natural handoff boundary.** The miner's job ends when it writes `supportOf` records. PLN's job begins when it receives those records as `Sentence` atoms. `miner-pln-bridge.metta` is the translation layer at exactly this boundary.

3. **It does not pollute the mining algorithm.** The `frequent-pattern-miner` remains a pure counting engine. `pattern-miner.metta` adds the PLN layer on top without changing any mining logic.

4. **It enables bidirectional coupling in later iterations.** Because `&pln-beliefs` is a persistent global space (bound at the top of `pattern-miner.metta`), beliefs accumulated from one mining run are available to influence the next run — enabling the iterative feedback loop described in the architecture.

---

## 3. What the Integration Actually Adds

| Without PLN | With PLN Integration |
|-------------|----------------------|
| Patterns are isolated support counts | Patterns become probabilistic beliefs linked to each other |
| No inference over mined rules | Modus Ponens, Deduction, Abduction fire on mined rules |
| No uncertainty propagation | Confidence flows through inference chains |
| Redundant patterns not merged across runs | `Truth_Revision` combines evidence from multiple sources |
| Cannot combine mined rules with domain axioms | PLN chains empirical rules with external knowledge |
| No pruning of logically impossible conjunctions | PLN contradiction check in `checker()` skips impossible candidates |
| Redundant output accumulates across iterations | PLN can filter already-explained patterns from being re-added |

---
+-----------------------------------------+
|       Distributed Atomspace (DAS)       |
|         & MeTTa Hypergraph KB           |
+----+-------------------------------+----+
     |                               |
     v                               |
+---------------------------+   +--------------------------+
|   hyperon-miner family    +-->| PLN / lib_pln            |
|   (Pattern Mining Loop)   |   |                          |
+-------------+-------------+   +-------------+------------+
              ^                               |
              +-------------------------------+
                    Logical Constraints
                    & Prior Probabilities

## 4. The Bridge File's Role (miner-pln-bridge.metta)

`miner-pln-bridge.metta` is not part of the miner and not part of PLN. It is a **translation and orchestration layer** that:

1. **Translates** `supportOf` atoms (miner output) into `Sentence` atoms (PLN input) with correct `stv` values derived from support counts.

2. **Derives directional Implication rules** from binary conjunctions (e.g. A∧B with support → both A→B and B→A with conditional probability as strength).

3. **Runs PLN inference rules** (Modus Ponens, Deduction, Revision, Abduction) on the resulting belief space.

4. **Stores derived conclusions** in `&pln-derived` — a separate space that tracks what was inferred (not what was observed), maintaining the distinction between empirical and rational knowledge.

The bridge could not live inside `frequent-pattern-miner/` (wrong layer), inside `lib_pln.metta` (PLN should not know about the miner), or inside `pattern-miner.metta` directly (would conflate orchestration with translation). It is a separate file by design.

---

## 5. Summary

PLN is integrated with Hyperon Pattern Miner at the `pattern-miner/` layer because:

1. **The miner produces statistically frequent patterns** but cannot evaluate their logical meaning, uncertainty, or relationships to other known facts.

2. **PLN is Hyperon's native uncertain reasoning engine**, using the same Atomese structures the miner already produces.

3. **The pattern-miner/ layer is the correct handoff point** — it sits above the mining algorithm and below the application layer, making it the natural place to translate statistical outputs into logical beliefs.

4. **Integrating at lower layers** (`frequent-pattern-miner/`, `truth-values/`) would violate separation of concerns and create circular dependencies.

The result is a system where **mining and reasoning reinforce each other**: mining discovers patterns, PLN evaluates and extends them, and PLN's beliefs guide the next mining iteration toward more semantically meaningful regions of the pattern space.

---

## Related Documentation

- `MINER_TO_PLN_PIPELINE.md` - Technical architecture of the integration
- `miner-pln-bridge.metta` - Implementation of the translation layer
- `tests/test_pln_wired_pipeline.metta` - Integration tests demonstrating the full pipeline
