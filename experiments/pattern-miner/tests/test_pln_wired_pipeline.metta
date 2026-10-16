
;; Wired PLN pipeline integration test
;; Test 3 uses the repository's ugly_man_sodaDrinker dataset.

!(import! &self "../../utils/surp-utils/boost_petta.py")
!(import! &self ../../utils/common-utils)
!(import! &self ../../utils/index_to_var)
!(import! &self ../../utils/constants)
!(import! &self ../../utils/TruthValue)
!(import! &self ../../utils/surp-utils/partition-metta)
!(import! &self ../../utils/surp-utils/binomialMetta)
!(import! &self ../../utils/surp-utils/surp-utils)
!(import! &self ../../utils/surp-utils/IIsurp_utils)
!(import! &self ../../utils/sort)
!(import! &self ../../utils/variable-combinations)
!(import! &self ../../utils/surp-utils/blk-abstractness)
!(import! &self ../../utils/remove_useless_clauses)
!(import! &self ../../utils/surp-utils/eq-prob-petta)
!(import! &self ../../utils/surp-utils/bs-utils)
!(import! &self ../../truth-values/est-tv)
!(import! &self ../../truth-values/emp-tv)
!(import! &self ../../surprisingness/emp-prob)
!(import! &self ../../surprisingness/isurp)
!(import! &self ../../surprisingness/isurp-old)
!(import! &self ../../surprisingness/IIsurp-old)
!(import! &self ../../frequent-pattern-miner/valuation)
!(import! &self ../../frequent-pattern-miner/shallow-abstractions)
!(import! &self ../../frequent-pattern-miner/specialization)
!(import! &self ../../frequent-pattern-miner/candidate)
!(import! &self ../../frequent-pattern-miner/conjunction-expansion)
!(import! &self ../../frequent-pattern-miner/frequent-pattern-miner-generic)
;; Load the remote PLN package, bridge, core miner, and optional wrapper in
;; order. The core miner itself does not import or call PLN.
!(import! &self (library lib_import))
;; Fetch PLN from GitHub into hyperon-miner/repos (ignored by Git).
;; Three parent steps from this test directory reach the repository root.
!(git-import! "https://github.com/trueagi-io/PLN.git" "" "../../../repos")
!(import! &self ../miner-pln-bridge)
!(import! &self ../pattern-miner)
!(import! &self ../miner-pln-integration)

;; TEST 1 checks the basic miner→PLN belief handoff.
!(bind! &db (new-space))
!(add-atom &db (Inheritance Alice sodaDrinker))
!(add-atom &db (Inheritance Alice human))


;!(bind! &res1 (new-space))

;!(println! "=== TEST 1: Mining (depth=0, minsup=1) ===")
;!(pattern-miner &res1 &db $x 1 0 none none none False)

;!(println! "--- PLN Beliefs after mining ---")
;!(collapse (match &pln-beliefs (Sentence ($p (stv $s $c)) $ev) ($p (stv $s $c))))

;!(assertEqual
;    (match &pln-beliefs (Sentence ($pattern (stv $s $c)) $evidence) Found)
;    Found)

;!(println! "TEST 1 PASSED: &pln-beliefs populated with mined STV sentences")



;!(println! "=== TEST 2: Step B — PLN Modus Ponens (top-level call) ===")

;!(add-atom &pln-beliefs
;    (Sentence
;        ((Implication
;            (Inheritance Alice sodaDrinker)
;            (Inheritance Alice healthyHabitRisk))
;         (stv 0.85 0.75))
;        ((ExpertRule1))))

;!(println! "--- Implication beliefs in &pln-beliefs ---")
;!(collapse (match &pln-beliefs
;    (Sentence ((Implication $ant $con) $tv) $ev)
;    (Implication $ant $con)))

;; Top-level call — PeTTa always evaluates these correctly
;!(run-pln-modus-ponens &pln-beliefs &pln-derived)

;!(println! "--- Derived sentences in &pln-derived ---")
;!(collapse (match &pln-derived $d $d))

;!(assertEqual
;    (let $derived
;            (collapse (match &pln-derived
;                (Sentence ($conclusion (stv $s $c)) $ev)
;                Found))
;        (if (== $derived ()) Fail (car-atom $derived)))
;    Found)

;!(println! "TEST 2 PASSED: &pln-derived contains PLN Modus Ponens conclusions")

;; TEST 3: Start from the unary ugly seed. T

!(println! "=== TEST 3: Mine rule and derive from it ===")
!(bind! &pln-beliefs (new-space))
!(bind! &pln-derived (new-space))
!(bind! &rule-db (new-space))
!(import! &rule-db ../../data/ugly_man_sodaDrinker)


!(bind! &cndpspace (new-space))
!(bind! &conjspace (new-space))
!(bind! &res-rule (new-space))
!(miner-pln-pipeline &res-rule &rule-db
    (Inheritance $person ugly)
    5 0 none none none True PatternMinerDataset &pln-beliefs)

!(println! "--- All mined results (including conjunction expansions) ---")
!(collapse (match &res-rule $result $result))

!(println! "--- Mined binary conjunction ---")
!(println!
    (collapse
        (match &res-rule
            (supportOf (, (Inheritance $x ugly)
                           (Inheritance $x human)) $support)
            (supportOf (, (Inheritance $x ugly)
                           (Inheritance $x human)) $support))))

!(assertEqual
    (match &res-rule
        (supportOf (, (Inheritance $x ugly)
                       (Inheritance $x human)) $support)
        Found)
    Found)

!(println! "--- Discovered man and woman conjunctions ---")
!(println!
    (collapse
        (match &res-rule
            (supportOf (, (Inheritance $x ugly)
                           (Inheritance $x $gender)) $support)
            (if (or (== $gender man) (== $gender woman))
                (supportOf (, (Inheritance $x ugly)
                               (Inheritance $x $gender)) $support)
                ()))))

!(assertEqual
    (match &res-rule
        (supportOf (, (Inheritance $x ugly)
                       (Inheritance $x man)) 5)
        Found)
    Found)
!(assertEqual
    (match &res-rule
        (supportOf (, (Inheritance $x ugly)
                       (Inheritance $x woman)) 5)
        Found)
    Found)

!(println! "--- Mined PLN implication ---")
!(collapse
    (match &pln-beliefs
        (Sentence
            ((Implication (Inheritance $x ugly)
                          (Inheritance $x human))
             (stv $strength $confidence))
            $evidence)
        (Sentence
            ((Implication (Inheritance $x ugly)
                          (Inheritance $x human))
             (stv $strength $confidence))
            $evidence)))

!(assertEqual
    (match &pln-beliefs
        (Sentence
            ((Implication (Inheritance $x ugly)
                          (Inheritance $x human))
             (stv $strength $confidence))
            $evidence)
        Found)
    Found)

!(println! "--- Check second mined rule: ugly → man ---")
!(println!
    (collapse
        (match &pln-beliefs
            (Sentence
                ((Implication (Inheritance $x ugly)
                              (Inheritance $x man))
                 (stv $strength $confidence))
                $evidence)
            (Sentence
                ((Implication (Inheritance $x ugly)
                              (Inheritance $x man))
                 (stv $strength $confidence))
                $evidence))))

!(assertEqual
    (match &pln-beliefs
        (Sentence
            ((Implication (Inheritance $x ugly)
                          (Inheritance $x man))
             (stv $strength $confidence))
            $evidence)
        Found)
    Found)

;; Mined-pattern strength divides by total database content (60 facts).
!(assertEqual
    (miner-db-size &rule-db)
    60)
!(assertEqual
    (miner-support-to-strength
        (Inheritance $person ugly) 10 &rule-db)
    (/safe 10 60))
!(assertEqual
    (miner-support-to-strength
        (, (Inheritance $person ugly) (Inheritance $person human))
        10 &rule-db)
    (/safe 10 60))
;; Every pattern shape uses the same total-content denominator.
!(assertEqual
    (miner-support-to-strength
        (Evaluation $person likes soda) 4 &rule-db)
    (/safe 4 60))
!(assertEqual
    (match &pln-beliefs
        (Sentence
            ((Inheritance $person ugly) (stv $strength $confidence))
            $evidence)
        Found)
    Found)
!(assertEqual
    (match &pln-beliefs
        (Sentence
            ((, (Inheritance $person ugly) (Inheritance $person human))
             (stv $strength $confidence))
            $evidence)
        Found)
    Found)
!(println! "TEST 3 CHECK PASSED: pattern strengths use total database content")


;; Add a query premise: Alaura is ugly (with independent evidence)
!(add-atom &pln-beliefs
    (Sentence ((Inheritance Alaura ugly) (stv 1.0 1.0))
              ((ExternalQuery Alaura))))
;; A second independent query exercises the separately mined ugly → man rule.
!(add-atom &pln-beliefs
    (Sentence ((Inheritance Allen ugly) (stv 1.0 1.0))
              ((ExternalQuery Allen))))

!(println! "--- DEBUG: Check if ugly→sodaDrinker rule exists ---")
!(println!
    (collapse
    (match &pln-beliefs
        (Sentence
            ((Implication (Inheritance $x ugly)
                          (Inheritance $x sodaDrinker))
             (stv $strength $confidence))
            $evidence)
        (Sentence
            ((Implication (Inheritance $x ugly)
                          (Inheritance $x sodaDrinker))
             (stv $strength $confidence))
            $evidence))))

!(assertEqual
    (match &pln-beliefs
        (Sentence
            ((Implication (Inheritance $x ugly)
                          (Inheritance $x sodaDrinker))
             (stv $strength $confidence))
            $evidence)
        Found)
    Found)

!(bind! &rule-derived (new-space))
!(run-pln-modus-ponens &pln-beliefs &rule-derived)

!(println! "--- All conclusions in &rule-derived ---")
!(collapse (match &rule-derived $x $x))

!(println! "--- Conclusion from mined rule: should derive Alaura sodaDrinker ---")
!(println!
    (collapse
        (match &rule-derived
            (Sentence ((Inheritance Alaura sodaDrinker)
                       (stv $strength $confidence))
                      $evidence)
            (Sentence ((Inheritance Alaura sodaDrinker)
                       (stv $strength $confidence))
                      $evidence))))

!(assertEqual
    (match &rule-derived
        (Sentence ((Inheritance Alaura sodaDrinker)
                   (stv $strength $confidence))
                  $evidence)
        Found)
    Found)

!(println! "--- Second conclusion: ugly → man should derive Allen man ---")
!(println!
    (collapse
        (match &rule-derived
            (Sentence ((Inheritance Allen man)
                       (stv $strength $confidence))
                      $evidence)
            (Sentence ((Inheritance Allen man)
                       (stv $strength $confidence))
                      $evidence))))

!(assertEqual
    (match &rule-derived
        (Sentence ((Inheritance Allen man)
                   (stv $strength $confidence))
                  $evidence)
        Found)
    Found)

!(println! "TEST 3 PASSED: mined ugly→sodaDrinker and ugly→man rules derived query conclusions")

;; TEST 4: Query a separate, manually supplied human→mortal rule.


!(println! "=== TEST 4: Query Charlie's mortality ===")

!(add-atom &pln-beliefs
    (Sentence ((Inheritance Charlie ugly) (stv 1.0 1.0))
              ((NewObservation))))
!(add-atom &pln-beliefs
    (Sentence ((Implication (Inheritance $x human)
                            (Inheritance $x mortal))
               (stv 1.0 0.99))
              ((BiologicalFact))))
!(println!
    (pln-query-from-beliefs
        &charlie-query-beliefs (Inheritance Charlie mortal) 100))
!(assertEqual
    (let $answer
            (pln-query-from-beliefs
               &pln-beliefs (Inheritance Charlie mortal) 100)
        (if (== $answer ()) Fail Found))
    Found)
    
!(println! "TEST 4 PASSED: PLN.Query derived Charlie mortal from human→mortal")

!(println! "=== TEST 5: PLN.Query on a mined-rule conclusion ===")
!(println!
    (pln-query-from-beliefs
        &pln-beliefs (Inheritance Alaura sodaDrinker) 100))
!(assertEqual
    (let $answer
            (pln-query-from-beliefs
                &pln-beliefs (Inheritance Alaura sodaDrinker) 100)
        (if (== $answer ()) Fail Found))
    Found)
!(println! "TEST 5 PASSED: PLN.Query derived the conclusion from the mined rule")


!(println! "=== TEST 6: PLN.Derive with a mined rule ===")
!(bind! &derive-test-beliefs (new-space))
!(add-atom &derive-test-beliefs
    (Sentence ((Inheritance Alaura ugly) (stv 1.0 1.0))
              ((DeriveTestPremise))))
!(let $mined-rule
       (car-atom
           (collapse
               (match &pln-beliefs
                   (Sentence
                       ((Implication (Inheritance $person ugly)
                                     (Inheritance $person human))
                        $rule-tv)
                       $rule-evidence)
                   (Sentence
                       ((Implication (Inheritance $person ugly)
                                     (Inheritance $person human))
                        $rule-tv)
                       $rule-evidence))))
   (add-atom &derive-test-beliefs $mined-rule))
!(let* (
       ($initial-beliefs
           (collapse (match &derive-test-beliefs $sentence $sentence)))
       ($derive-result
           (PLN.Derive $initial-beliefs $initial-beliefs 10))
       ($derived-beliefs (car-atom (cdr-atom $derive-result)))
       (true (println! ("PLN.Derive belief state:" $derived-beliefs)))
       ($found
           (collapse
               (case (superpose $derived-beliefs)
                   (((Sentence ((Inheritance Alaura human) $tv) $ev)
                     Found)))))
       ($assert
           (assertEqual
               (if (== $found ()) Fail Found)
               Found)))
       True)
!(println! "TEST 6 PASSED: PLN.Derive used the mined ugly→human rule")

!(println! "=== ALL WIRED PIPELINE TESTS PASSED ===")
