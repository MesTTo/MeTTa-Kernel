;Subtyping, and the two things about it that surprise people.
;
;The FIRST is the spelling. It is `:<`, not `:>`, and the arrow points from the
;subtype UP to the supertype: read `(:< Dog Animal)` as "Dog is below Animal".
;That is upstream's SUB_TYPE_SYMBOL and the direction is fixed by it, so a
;`(:> Animal Dog)` written the other way round is not a subtype edge at all,
;just an ordinary atom nobody reads.
;
;The SECOND is the mechanism, and it is not what the name suggests. Nothing
;here DECIDES whether one type is below another while checking an argument.
;Declaring an edge WIDENS a value's type list, and the ordinary type check then
;runs unchanged against the wider list. So the matcher learns nothing about
;subtyping, and `get-type` is where the whole feature is visible.

(: Rex Dog)
(:< Dog Animal)

;One value, two types now, in declaration order and then supertype order.
!(test (collapse (get-type Rex)) (Dog Animal))

;Which is what makes an argument acceptable: `speak` asks for an Animal and Rex
;is a Dog, and the check passes because Animal is in Rex's widened list.
(: speak (-> Animal String))
(= (speak $a) "some noise")
!(test (speak Rex) "some noise")

;It is transitive, because widening repeats over what the previous round added.
(:< Animal LivingThing)
!(test (collapse (get-type Rex)) (Dog Animal LivingThing))

;Two things are NOT widened, and both are deliberate: a grounded literal's
;built-in type, and the return type of an application. The type graph is read
;for symbols and expressions only.
(:< Number Countable)
!(test (collapse (get-type 1)) (Number))

(: half (-> Number Fraction))
(:< Fraction Rational)
!(test (collapse (get-type (half 3))) (Fraction))

;A diamond answers its join TWICE, and that is not a bug to report. Widening
;checks what is already present against the list as it stood when the round
;BEGAN, so Bird and Mammal both reach Animal2 in the same round and both append
;it. Answering more tidily than the reference implementation would still be
;answering differently.
(:< Bat Bird)
(:< Bat Mammal)
(:< Bird Animal2)
(:< Mammal Animal2)
(: Stellaluna Bat)
!(test (collapse (get-type Stellaluna)) (Bat Bird Mammal Animal2 Animal2))

;An edge whose subtype side is a PATTERN contributes an instance, because the
;lookup is the ordinary two-sided matcher rather than a table of symbols.
(:< (Boxed $t) Container)
(: crate (Boxed Apple))
!(test (collapse (get-type crate)) ((Boxed Apple) Container))
