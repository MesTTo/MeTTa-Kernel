; Purpose: show ground expressions as isolated space names whose parameters
; are visible through context-space.

!(new-space (cache &primary-kb 100))
!(new-space (cache &secondary-kb 10))

;The same equation reads the identifier of whichever instance owns it. Pattern
;destructuring is the parameter surface, so no second parameter builtin exists.
!(add-atom
   (cache &primary-kb 100)
   (= (cache-config)
      (let (cache $base $limit)
           (context-space)
           (config $base $limit))))
!(add-atom
   (cache &secondary-kb 10)
   (= (cache-config)
      (let (cache $base $limit)
           (context-space)
           (config $base $limit))))

!(add-atom (cache &primary-kb 100) (entry primary))
!(add-atom (cache &secondary-kb 10) (entry secondary))

!(test
   (evalc (cache-config) (cache &primary-kb 100))
   (config &primary-kb 100))
!(test
   (evalc (cache-config) (cache &secondary-kb 10))
   (config &secondary-kb 10))
!(test
   (collapse (match (cache &primary-kb 100) (entry $which) $which))
   (primary))
!(test
   (collapse (match (cache &secondary-kb 10) (entry $which) $which))
   (secondary))
!(test (get-type (cache &primary-kb 100)) SpaceType)
