;; Load PLN from the MeTTa library registry; entry points should run
;; `git-import!` for PLN before importing this bridge.
!(import! &self (library PLN lib_pln))


;; Dataset-size helpers

(= (miner-db-size $db)
   (length (collapse (match $db $x $x))))


;; Truth-value primitives


(= (miner-support-to-strength $pattern $support $db)
   ;; Use support / total database atom count. Empty databases yield 0.0.
   (let $denominator (miner-db-size $db)
       (if (> $denominator 0)
           (/safe $support $denominator)
           0.0)))

(= (miner-pattern-confidence-k) 1.0)

(= (miner-support-to-confidence $support)
   (/ $support (+ $support (miner-pattern-confidence-k))))

(= (mined-pattern-to-pln-sentence $pattern $support $db $dataset-id)
   (let*
       (
           ($strength (miner-support-to-strength $pattern $support $db))
           ($confidence (miner-support-to-confidence $support))
           ($stamp
               (cons-atom
                   (MinerPatternEvidence $dataset-id $pattern $support)
                   ()))
       )
       (Sentence ($pattern (stv $strength $confidence)) $stamp)))


;; Conditional implication rules (binary conjunctions)
;; Convert an ordered side of a mined binary conjunction to a rule. Strength
;; estimates P(consequent | antecedent); confidence reflects antecedent support.
(= (store-mined-conditional-rule $antecedent $consequent $joint-support
                                 $db $dataset-id $belief-space)
   (let*
       (
           ($antecedent-support (sup-num $db $antecedent))
           ($valid (and (> $antecedent-support 0)
                        (<= $joint-support $antecedent-support)))
           ($strength (/safe $joint-support $antecedent-support))
           ($confidence (miner-support-to-confidence $antecedent-support))
           ($evidence
               (cons-atom
                   (MinerPatternRuleEvidence $dataset-id $antecedent
                                             $consequent $joint-support
                                             $antecedent-support)
                   ()))
           ($rule
               (Sentence ((Implication $antecedent $consequent)
                          (stv $strength $confidence))
                         $evidence))
       )
       (if $valid (add-atom $belief-space $rule) True)))

(= (store-mined-binary-rule (, $first $second)
                            $joint-support $db $dataset-id $belief-space)
   (let*
       (
           ($forward
               (store-mined-conditional-rule
                   $first $second $joint-support $db $dataset-id $belief-space))
           ($reverse
               (store-mined-conditional-rule
                   $second $first $joint-support $db $dataset-id $belief-space))
       )
       True))

(= (store-mined-binary-rule $pattern $support $db $dataset-id $belief-space)
   True)


;; Convert each supportOf atom in the collapsed result list.
(= (store-mined-pattern-results $results $db $dataset-id $belief-space)
   (if (== $results ())
       ()
       (let*
           (
               ($result (car-atom $results))
               ($tail (cdr-atom $results))
               ((supportOf $pattern $support) $result)
               ($sentence
                   (mined-pattern-to-pln-sentence
                       $pattern $support $db $dataset-id))
               ($add
                   (add-atom $belief-space $sentence))
               ($add-rule
                   (store-mined-binary-rule
                       $pattern $support $db $dataset-id $belief-space))
               ($rest
                   (store-mined-pattern-results
                       $tail $db $dataset-id $belief-space))
           )
           $rest)))

(= (miner-results-to-pln-beliefs $results $db $dataset-id $belief-space)
   (store-mined-pattern-results
       $results $db $dataset-id $belief-space))



;; 
;; Modus Ponens
;; 

(= (derive-mined-pattern-beliefs
       $belief-space $task-pattern $antecedent-pattern $derived-space)
   (let*
       (
           ($task-matches
               (collapse
                   (match $belief-space
                       (Sentence ($task-pattern $truth-value) $evidence)
                       (Sentence ($task-pattern $truth-value) $evidence))))
           ($antecedent-matches
               (collapse
                   (match $belief-space
                       (Sentence ($antecedent-pattern $truth-value) $evidence)
                       (Sentence ($antecedent-pattern $truth-value) $evidence))))
           ((Sentence ($implication $rule-tv) $rule-evidence)
               (car-atom $task-matches))
           ((Sentence ($antecedent-pattern $premise-tv) $premise-evidence)
               (car-atom $antecedent-matches))
       )
       (if (StampDisjoint $premise-evidence $rule-evidence)
           (let*
               (
                   ;; This is exactly PLN's Modus Ponens rule from lib_pln.metta.
                   (($conclusion $derived-tv)
                       (|- ($antecedent-pattern $premise-tv)
                           ($implication $rule-tv)))
                   ($stamp (StampConcat $premise-evidence $rule-evidence))
                   ($derived-belief
                       (Sentence ($conclusion $derived-tv) $stamp))
                   ($print
                       (println! ("PLN Modus Ponens result:" $derived-belief)))
                   ($store
                       (add-atom $derived-space $derived-belief))
               )
               $store)
           (println! "PLN Modus Ponens skipped: evidence stamps overlap"))))


(= (store-pln-mp-matches () $derived-space) True)
(= (store-pln-mp-matches $matches $derived-space)
   (let*
       (
           ($item (car-atom $matches))
           ($rest (cdr-atom $matches))
           ((MpMatch $antecedent $conclusion $premise-tv $premise-evidence
                     $rule-tv $rule-evidence) $item)
           ($derived
               (if (StampDisjoint $premise-evidence $rule-evidence)
                   (|- ($antecedent $premise-tv)
                       ((Implication $antecedent $conclusion) $rule-tv))
                   ()))
           ($store
               (if (== $derived ())
                   True
                   (let*
                       (
                           (($derived-pattern $derived-tv) $derived)
                           ($derived-evidence
                               (StampConcat $premise-evidence $rule-evidence))
                           ($belief
                               (Sentence ($derived-pattern $derived-tv)
                                         $derived-evidence))
                       )
                       (add-atom $derived-space $belief))))
           ($continue (store-pln-mp-matches $rest $derived-space))
       )
       True))

(= (run-pln-mp-with-rules $belief-space () $derived-space) True)
(= (run-pln-mp-with-rules $belief-space $rules $derived-space)
   (let*
       (
           ($rule (car-atom $rules))
           ($rest (cdr-atom $rules))
           ((Sentence ((Implication $antecedent $conclusion) $rule-tv)
                      $rule-evidence) $rule)
     
           ($matches
               (collapse
                   (match $belief-space
                       (Sentence ($antecedent $premise-tv) $premise-evidence)
                       (MpMatch $antecedent $conclusion $premise-tv
                                $premise-evidence $rule-tv $rule-evidence))))
           ($store (store-pln-mp-matches $matches $derived-space))
           ($continue (run-pln-mp-with-rules
                           $belief-space $rest $derived-space))
       )
       True))

(= (run-pln-modus-ponens $belief-space $derived-space)
   (let*
       (
           ($rules
               (collapse
                   (match $belief-space
                       (Sentence ((Implication $antecedent $conclusion) $truth-value) $evidence)
                       (Sentence ((Implication $antecedent $conclusion) $truth-value) $evidence))))
           ($derive
               (run-pln-mp-with-rules
                   $belief-space $rules $derived-space))
       )
       True))

;; ---------------------------------------------------------------
;; PLN.Query wrapper
;; ---------------------------------------------------------------
;; Converts a belief space to a list and runs PLN's agenda-based reasoner
;; for a bounded query. This is separate from the removed repeated forward
;; chaining helper.

(= (pln-query-from-beliefs $belief-space $query-atom $max-steps)
   (let $beliefs (collapse (match $belief-space $s $s))
       (PLN.Query $beliefs $query-atom $max-steps)))

(= (pln-query-from-beliefs $belief-space $query-atom)
   (pln-query-from-beliefs $belief-space $query-atom (PLN.Config.MaxSteps)))
