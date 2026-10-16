;; Optional Miner → PLN integration wrapper.
;; 

!(bind! &cndpspace (new-space))
!(bind! &conjspace (new-space))

(= (pln-pipeline-is-ground-inheritance-seed
       (Inheritance $subject $property))
   (if (== (get-metatype $property) Variable) False True))
(= (pln-pipeline-is-ground-inheritance-seed $pattern) False)

(= (pln-pipeline-discover-seeded-properties $db $seed-property)
   (let*
       (
           ($facts
               (collapse
                   (match $db
                       (Inheritance $subject $property)
                       (Inheritance $subject $property))))
           ($properties
               (pln-pipeline-properties-from-facts
                   $facts $db $seed-property))
       )
       (unique-atom $properties)))

(= (pln-pipeline-properties-from-facts () $db $seed-property)
   ())
(= (pln-pipeline-properties-from-facts
       $facts $db $seed-property)
   (let*
       (
           ($fact (car-atom $facts))
           ($tail (cdr-atom $facts))
           ((Inheritance $subject $property) $fact)
           ($seed-match
               (collapse
                   (match $db (Inheritance $subject $seed-property) True)))
           ($entry
               (if (or (== $seed-match ())
                       (== $property $seed-property))
                   ()
                   $property))
           ($rest
               (pln-pipeline-properties-from-facts
                   $tail $db $seed-property))
       )
       (if (== $entry ()) $rest (cons-atom $entry $rest))))

(= (pln-pipeline-count-conjunctions () $db $seed-property $minsup)
   ())
(= (pln-pipeline-count-conjunctions
       $properties $db $seed-property $minsup)
   (let*
       (
           ($property (car-atom $properties))
           ($tail (cdr-atom $properties))
           ($candidate
               (replacev
                   (, (Inheritance Z $seed-property)
                      (Inheritance Z $property))))
           ($support (sup-num $db $candidate))
           ($entry
               (if (>= $support $minsup)
                   (supportOf $candidate $support)
                   ()))
           ($rest
               (pln-pipeline-count-conjunctions
                   $tail $db $seed-property $minsup))
       )
       (if (== $entry ()) $rest (cons-atom $entry $rest))))

;; For a depth-zero property seed, mine the unary seed first, then discover
;; and count co-occurring properties. Other calls use the generic miner path.
(= (pln-pipeline-frequency-results
       $db $initpat $minsup $depth $conj-exp)
   (let*
       (
           ($results
               (if (and $conj-exp
                        (and (== $depth 0)
                             (pln-pipeline-is-ground-inheritance-seed
                                 $initpat)))
                   (let*
                       (
                           (true (println! "==== Shared-property discovery started ====="))
                           ($base
                               (collapse
                                   (frequency-pattern-miner
                                       $db $initpat &cndpspace &conjspace
                                       $minsup $depth False)))
                           (true (println! "==== Unary seed mining and formatting returned ====="))
                           ((Inheritance $subject $seed-property) $initpat)
                           ($properties
                               (pln-pipeline-discover-seeded-properties
                                   $db $seed-property))
                           ($extensions
                               (pln-pipeline-count-conjunctions
                                   $properties $db $seed-property $minsup))
                           (true
                               (println!
                                   ("==== Shared-property candidates discovered ====="
                                    (size-atom $extensions))))
                       )
                       (unique-atom (append $base $extensions)))
                   (collapse
                       (frequency-pattern-miner
                           $db $initpat &cndpspace &conjspace
                           $minsup $depth $conj-exp))))
           ($commit (cut))
       )
       $results))

(= (pln-pipeline-store-miner-results
       $kb $db () $surp-mode $normalization $db-ratio)
   True)
(= (pln-pipeline-store-miner-results
       $kb $db $results $surp-mode $normalization $db-ratio)
   (let*
       (
           ($result (car-atom $results))
           ($tail (cdr-atom $results))
           ($handled
               (call-surprisingness
                   $kb $db $result $surp-mode $normalization $db-ratio))
           ($rest
               (pln-pipeline-store-miner-results
                   $kb $db $tail $surp-mode $normalization $db-ratio))
           ($commit (cut))
       )
       True))

;; Run mining once, save its normal output, and send the same support records
;; to the PLN bridge. The caller chooses the target belief space and dataset ID.
(= (miner-pln-pipeline
       $kb $db $initpat $minsup $depth $surp-mode $normalization $db-ratio
       $conj-exp $dataset-id $belief-space)
   (let*
       (
           (true (println! "==== Pattern Miner Started ====="))
           ($results
               (pln-pipeline-frequency-results
                   $db $initpat $minsup $depth $conj-exp))
           (true (println! ("==== Pattern Miner Results =====" $results)))
           ($stored
               (pln-pipeline-store-miner-results
                   $kb $db $results $surp-mode $normalization $db-ratio))
           (true
               (println! ("==== Pattern results ready for PLN bridge ====="
                          (size-atom $results))))
           ($bridge-result
               (miner-results-to-pln-beliefs
                   $results $db $dataset-id $belief-space))
           (true (println! "==== PLN bridge returned ====="))
           ($commit (cut))
       )
       $results))
