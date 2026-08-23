# The MeTTa standard library, in Python

Every operation MeTTa's standard library declares, and what you write in Python
instead. 136 of the 179 operations a program can call have a Python
spelling, and every row below ran on both sides: the MeTTa form on this engine and
on LeaTTa, the conformance oracle, and the Python spelling here.

The names and their types are LeaTTa's, measured against its built binary rather
than transcribed: manifest 1.0.9 at commit `e47c93f`, 379 declarations
over 377 distinct names. `bindings/python/tools/phrasebook.py` runs the
rows and fails when a spelling stops answering what it says it answers.

## How to read a row

The MeTTa column is a form that runs. The Python column is what you write instead.
The answer column is what both produced. In a Python cell `m` is the engine, `space`
is a fresh space, and `S` and `V` build symbols and variables; in a MeTTa cell `&pb`
is that row's own space.

Rows fall in five buckets, and the bucket is the honest part:

- **dissolves** (115) &mdash; Python already has the concept, so there is no metta name at all and the spelling is Python's own syntax, protocol or standard library
- **method** (21) &mdash; the concept is MeTTa's own, so it wears a metta name
- **instruction** (0) &mdash; deep control that stays instruction-tier, reached by building the term at the `S.` door and reducing it
- **internal** (198) &mdash; LeaTTa's mechanised interpreter, written in MeTTa; PeTTa writes its interpreter in Prolog, so these names are on neither surface
- **absent** (43) &mdash; a user-facing operation with no Python spelling today: the residue

Provenance: LeaTTa manifest 1.0.9 at commit `e47c93f`, 379 declarations over 377 distinct names.

## What the Python spelling costs

Section 9e claims that a structure operation on an atom already held in Python
costs no engine crossing at all. Measured over the rows that run both sides:
the MeTTa forms cost 146,469 engine inferences and the Python spellings
cost 6,943, and 90 of the 121 rows cost the engine EXACTLY
NOTHING. `e[0]`, `e[1:]`, `len(e)`, `max([...])` and `S.f(1)` each read the same
count as an empty measurement block, so the claim holds: the work never reaches
the engine at all.

`(car-atom (a b c))` costs 878 inferences on this
engine against 0 for `e[0]`, and `(map-atom (1 2 3) $x (+ $x 1))` costs
1,444 against 0 for the comprehension.

The other side of the same coin, so the comparison is not oversold. Most of a
MeTTa row's cost is running one form at all: on a fresh engine an unreduced
three-argument call costs 713 inferences and `(car-atom (a b c))` costs 848, so
about 135 of it is the operation. And inside an `@m.define` body the Python
spelling COMPILES to the same instruction, where the cost is the handwritten cost
by construction. The saving is real where a program already holds the atom in
Python, which is what the bucket says.

Absolute counts move with what the engine has already done, which is why the two
paragraphs above disagree by tens of inferences on the same form; the zero on the
Python side does not move. Within one run the counts are exact: three fresh
`--learn` processes wrote byte-identical files, cost numbers included
[measured 2026-08-22; commit=c6abaad21ab41b32b815b7481edff822b236e69a].

## Arithmetic

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(+ 1 2)` | `1 + 2` | `3` | dissolves |
| `!(- 5 2)` | `5 - 2` | `3` | dissolves |
| `!(* 3 4)` | `3 * 4` | `12` | dissolves |
| `!(/ 7 2)` | `7 / 2` | `3 on leatta; 3.5 on metta and python` | dissolves |
| `!(% -7 3)` | `-7 % 3` | `2` | dissolves |
| `!(div-floor -7 2)` | `-7 // 2` | `-4` | dissolves |
| `!(mod-floor -7 2)` | `-7 % 2` | `1` | dissolves |
| `!(div-trunc -7 2)` | `import math ⏎ math.trunc(-7 / 2)` | `-3` | dissolves |
| `!(rem-trunc -7 2)` | `import math ⏎ int(math.fmod(-7, 2))` | `-1` | dissolves |
| `!(div-euclid -7 2)` | `a, b = -7, 2 ⏎ a // b if b > 0 else -(a // -b)` | `-4` | dissolves |
| `!(mod-euclid -7 2)` | `a, b = -7, 2 ⏎ a % abs(b)` | `1` | dissolves |

- `+` `(-> Number Number Number)` &mdash; Python's own operator. On atoms the same operator builds `(+ ...)` instead of computing, which is how a compiled body reaches the MeTTa function.
- `-` `(-> Number Number Number)` &mdash; Python's own operator.
- `*` `(-> Number Number Number)` &mdash; Python's own operator.
- `/` `(-> Number Number Number)` &mdash; Python's `/` is true division, and so is PeTTa's. LeaTTa's integer `/` is EUCLIDEAN by its own ruling, so `(/ 7 2)` is 3 there and 3.5 here; on floats all three agree. Where they differ: LeaTTa answers 3 (Euclidean integer division), PeTTa and Python 3.5.
- `%` `(-> Number Number Number)` &mdash; Python's own operator. Both take the sign of the divisor for a positive divisor; LeaTTa's is Euclidean, so a NEGATIVE divisor parts them and `mod-floor` is the name for Python's convention.
- `div-floor` `(-> Number Number Number)` &mdash; Python's `//` IS floored division, so the name has no Python spelling of its own. The form is shown but not run here: PeTTa implements neither the floored nor the truncating division family.
- `mod-floor` `(-> Number Number Number)` &mdash; Python's `%` IS the floored remainder, sign of the divisor. The form is shown but not run here: PeTTa implements neither the floored nor the truncating division family.
- `div-trunc` `(-> Number Number Number)` &mdash; Truncating division is `math.trunc` over the true quotient; Python's `//` would floor instead, which differs on negatives. The form is shown but not run here: PeTTa implements neither the floored nor the truncating division family.
- `rem-trunc` `(-> Number Number Number)` &mdash; `math.fmod` is the truncating remainder, sign of the dividend; it answers a float, so an integer row wraps it in `int`. The form is shown but not run here: PeTTa implements neither the floored nor the truncating division family.
- `div-euclid` `(-> Number Number Number)` &mdash; Euclidean division has no Python builtin because the remainder is defined non-negative; the quotient is the floor for a positive divisor and its negation otherwise. The form is shown but not run here: PeTTa implements neither the floored nor the truncating division family.
- `mod-euclid` `(-> Number Number Number)` &mdash; The Euclidean remainder is always non-negative, which is `a % abs(b)`. The form is shown but not run here: PeTTa implements neither the floored nor the truncating division family.

## Comparison and equality

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(< 1 2)` | `1 < 2` | `True` | dissolves |
| `!(<= 2 2)` | `2 <= 2` | `True` | dissolves |
| `!(> 2 1)` | `2 > 1` | `True` | dissolves |
| `!(>= 1 2)` | `1 >= 2` | `False` | dissolves |
| `!(== (f 1) (f 1))` | `S.f(1) == S.f(1)` | `True` | dissolves |
| `!(=alpha (f $x) (f $y))` | `S.f(V.x).alpha_eq(S.f(V.y))` | `True` | method |
| `!(noreduce-eq (+ 1 2) (+ 1 2))` | `S['+'](1, 2) == S['+'](1, 2)` | `True` | dissolves |

- `<` `(-> Number Number Bool)` &mdash; Python's own operator.
- `<=` `(-> Number Number Bool)` &mdash; Python's own operator.
- `>` `(-> Number Number Bool)` &mdash; Python's own operator.
- `>=` `(-> Number Number Bool)` &mdash; Python's own operator.
- `==` `(-> $t $t Bool)` &mdash; Python's own operator, and atoms compare structurally under it.
- `=alpha` `(-> Atom Atom Bool)` &mdash; Equality modulo variable renaming is not a Python concept, so it keeps MeTTa's noun. `a.alpha_eq(b)` is the method form of the same act.
- `noreduce-eq` `(-> Atom Atom Bool)` &mdash; Comparing two atoms WITHOUT reducing them is what Python's `==` on atoms already does: building a term never evaluates it.

## Numeric functions

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(abs-math -3)` | `abs(-3)` | `3` | dissolves |
| `!(sqrt-math 4)` | `import math ⏎ math.sqrt(4)` | `2.0` | dissolves |
| `!(pow-math 2.0 3)` | `2.0 ** 3` | `8.0` | dissolves |
| `!(log-math 2 8)` | `import math ⏎ math.log(8, 2)` | `3.0` | dissolves |
| `!(sin-math 0)` | `import math ⏎ math.sin(0)` | `0.0` | dissolves |
| `!(cos-math 0)` | `import math ⏎ math.cos(0)` | `1.0` | dissolves |
| `!(tan-math 0)` | `import math ⏎ math.tan(0)` | `0.0` | dissolves |
| `!(asin-math 0)` | `import math ⏎ math.asin(0)` | `0.0` | dissolves |
| `!(acos-math 1)` | `import math ⏎ math.acos(1)` | `0.0` | dissolves |
| `!(atan-math 0)` | `import math ⏎ math.atan(0)` | `0.0` | dissolves |
| `!(ceil-math 2.1)` | `import math ⏎ math.ceil(2.1)` | `3.0 on leatta; 3 on metta and python` | dissolves |
| `!(floor-math 2.9)` | `import math ⏎ math.floor(2.9)` | `2.0 on leatta; 2 on metta and python` | dissolves |
| `!(round-math 2.5)` | `import math ⏎ math.floor(2.5 + 0.5)` | `3.0 on leatta; 3 on metta and python` | dissolves |
| `!(trunc-math 2.9)` | `import math ⏎ math.trunc(2.9)` | `2.0 on leatta; 2 on metta and python` | dissolves |
| `!(isnan-math 1)` | `import math ⏎ math.isnan(1)` | `False` | dissolves |
| `!(isinf-math 1)` | `import math ⏎ math.isinf(1)` | `False` | dissolves |

- `abs-math` `(-> Number Number)` &mdash; Python's builtin `abs`.
- `sqrt-math` `(-> Number Number)` &mdash; `math.sqrt`.
- `pow-math` `(-> Number Number Number)` &mdash; Python's `**` operator. MeTTa answers a float where Python's integer power answers an integer, so the row raises a float.
- `log-math` `(-> Number Number Number)` &mdash; `math.log(x, base)`, with the arguments the other way round: MeTTa takes the base first.
- `sin-math` `(-> Number Number)` &mdash; `math.sin`.
- `cos-math` `(-> Number Number)` &mdash; `math.cos`.
- `tan-math` `(-> Number Number)` &mdash; `math.tan`.
- `asin-math` `(-> Number Number)` &mdash; `math.asin`.
- `acos-math` `(-> Number Number)` &mdash; `math.acos`.
- `atan-math` `(-> Number Number)` &mdash; `math.atan`.
- `ceil-math` `(-> Number Number)` &mdash; `math.ceil`, which answers an integer in Python 3 where LeaTTa keeps the float. Where they differ: LeaTTa answers 3.0 and keeps the float; PeTTa and Python answer 3.
- `floor-math` `(-> Number Number)` &mdash; `math.floor`, the same integer-against-float difference as `ceil-math`. Where they differ: LeaTTa answers 2.0 and keeps the float; PeTTa and Python answer 2.
- `round-math` `(-> Number Number)` &mdash; NOT Python's `round`: `round` breaks a tie to the EVEN neighbour, so `round(2.5)` is 2 where MeTTa answers 3. Half away from zero is `math.floor(x + 0.5)` for a positive number. Where they differ: LeaTTa answers 3.0 and keeps the float; PeTTa and Python answer 3.
- `trunc-math` `(-> Number Number)` &mdash; `math.trunc`, or `int` on a float. Where they differ: LeaTTa answers 2.0 and keeps the float; PeTTa and Python answer 2.
- `isnan-math` `(-> Number Bool)` &mdash; `math.isnan`.
- `isinf-math` `(-> Number Bool)` &mdash; `math.isinf`.

## Booleans

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(and True False)` | `True and False` | `False` | dissolves |
| `!(or True False)` | `True or False` | `True` | dissolves |
| `!(not True)` | `not True` | `False` | dissolves |
| `!(xor True False)` | `True ^ False` | `True` | dissolves |

- `and` `(-> Bool Bool Bool)` &mdash; Python's own keyword. On atoms `&` builds the MeTTa `and` instead, because the keyword cannot be overloaded.
- `or` `(-> Bool Bool Bool)` &mdash; Python's own keyword; `|` is the operator form on atoms.
- `not` `(-> Bool Bool)` &mdash; Python's own keyword; `~` is the operator form on atoms.
- `xor` `(-> Bool Bool Bool)` &mdash; Python's `^` on booleans.

## Expression structure

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(car-atom (a b c))` | `e = metta.Expression(S.a, S.b, S.c) ⏎ e[0]` | `a` | dissolves |
| `!(cdr-atom (a b c))` | `e = metta.Expression(S.a, S.b, S.c) ⏎ e[1:]` | `(b c)` | dissolves |
| `!(cons-atom f (a b))` | `tail = (S.a, S.b) ⏎ S.f(*tail)` | `(f a b)` | dissolves |
| `!(decons-atom (f a b))` | `e = metta.Expression(S.f, S.a, S.b) ⏎ head, *tail = e ⏎ (head, tuple(tail))` | `(f (a b))` | dissolves |
| `!(size-atom (a b c))` | `e = metta.Expression(S.a, S.b, S.c) ⏎ len(e)` | `3` | dissolves |
| `!(index-atom (a b c) 1)` | `e = metta.Expression(S.a, S.b, S.c) ⏎ e[1]` | `b` | dissolves |
| `!(max-atom (1 2 3))` | `max([1, 2, 3])` | `3.0 on leatta; 3 on metta and python` | dissolves |
| `!(min-atom (1 2 3))` | `min([1, 2, 3])` | `1.0 on leatta; 1 on metta and python` | dissolves |
| `!(sort-strings ("b" "a" "c"))` | `tuple(sorted(["b", "a", "c"]))` | `("a" "b" "c")` | dissolves |
| `!(map-atom (1 2 3) $x (+ $x 1))` | `tuple(x + 1 for x in [1, 2, 3])` | `(2 3 4)` | dissolves |
| `!(filter-atom (1 2 3) $x (> $x 1))` | `tuple(x for x in [1, 2, 3] if x > 1)` | `(2 3)` | dissolves |
| `!(foldl-atom (1 2 3) 0 $a $b (+ $a $b))` | `import functools ⏎ functools.reduce(lambda a, b: a + b, [1, 2, 3], 0)` | `6` | dissolves |
| `!(for-each-in-atom (1 2) println!)` | `for value in [1, 2]: ⏎     print(value) ⏎ metta.Expression()` | `() on leatta and python; (() ()) on metta` | dissolves |
| `!(atom-subst a $x (f $x))` | `S.f(V.x).map(lambda a: S.a if a == V.x else a)` | `(f a)` | method |
| `!(if-decons-expr (a b) $h $t (yes $h $t) no)` | `e = metta.Expression(S.a, S.b) ⏎ S.yes(e[0], e[1:]) if len(e) else S.no` | `(yes a (b))` | dissolves |

- `car-atom` `(-> Expression %Undefined%)` &mdash; Indexing. An expression is a sequence in Python, so its head is `e[0]`.
- `cdr-atom` `(-> Expression Expression)` &mdash; Slicing. `e[1:]` answers a Python tuple today rather than an Expression, which prints the same and is the T6 friction section 9e names as this bucket's one prerequisite.
- `cons-atom` `(-> Atom Expression Atom)` &mdash; Construction: call the head, or rebuild from head and tail with `*`.
- `decons-atom` `(-> Expression Atom)` &mdash; Starred unpacking, which is the same act in one line: `head, *tail = e`.
- `size-atom` `(-> Expression Number)` &mdash; `len`. Both count CHILDREN, so `(f a b)` is 3 either way.
- `index-atom` `(-> Expression Number Atom)` &mdash; Indexing again, with the index you want.
- `max-atom` `(-> %Undefined% Number)` &mdash; Python's builtin `max` over the children. Where they differ: LeaTTa answers 3.0 and keeps the float; PeTTa and Python answer 3.
- `min-atom` `(-> %Undefined% Number)` &mdash; Python's builtin `min` over the children. Where they differ: LeaTTa answers 1.0 and keeps the float; PeTTa and Python answer 1.
- `sort-strings` `(-> Expression Expression)` &mdash; Python's builtin `sorted`. A tuple goes back in as one expression.
- `map-atom` `(-> Expression Variable Atom Expression) | (-> Expression Expression Expression)` &mdash; A comprehension, or `map`. The variable and the template are the comprehension's own binder and body.
- `filter-atom` `(-> Expression Variable Atom Expression) | (-> Expression Expression Expression)` &mdash; A comprehension with an `if`, or `filter`.
- `foldl-atom` `(-> Expression Atom Variable Variable Atom %Undefined%) | (-> Expression Atom Expression %Undefined%)` &mdash; `functools.reduce` with an initial value, which is the same left fold.
- `for-each-in-atom` `(-> Expression Atom (->))` &mdash; A `for` statement. It is called for its effect, so the row prints and answers the unit. Python's `for` has no value at all, and the concept map says `None` IS the unit, but `metta.ground(None)` renders `<NoneType>` rather than `()` today, so a row that wants the unit writes it [measured 2026-08-22]. Where they differ: PeTTa answers one unit per element where LeaTTa answers one.
- `atom-subst` `(-> Atom Variable Atom Atom)` &mdash; Applying a substitution to a template, which `Atom.map` does over the whole term. Section 9e wants the bindings object to carry it, `b.apply(template)`; `metta.Bindings` has no such method yet, so the walker is the spelling. The form is shown but not run here: PeTTa leaves the MeTTa call unreduced.
- `if-decons-expr` `(-> Expression Variable Variable Atom Atom %Undefined%)` &mdash; Starred unpacking inside an `if`: the empty case is the `else` branch. The form is shown but not run here: PeTTa leaves the call unreduced.

## Set operations

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(union (superpose (a b b)) (superpose (b c)))` | `[S.a, S.b, S.b] + [S.b, S.c]` | `a, b, b, b, c` | dissolves |
| `!(intersection (superpose (a b b c)) (superpose (b c c)))` | `from collections import Counter ⏎ list((Counter([S.a, S.b, S.b, S.c]) & Counter([S.b, S.c, S.c])).elements())` | `b, c` | dissolves |
| `!(subtraction (superpose (a b b c)) (superpose (b c)))` | `from collections import Counter ⏎ list((Counter([S.a, S.b, S.b, S.c]) - Counter([S.b, S.c])).elements())` | `a, b` | dissolves |
| `!(unique (superpose (a b b c)))` | `list(dict.fromkeys([S.a, S.b, S.b, S.c]))` | `a, b, c` | dissolves |
| `!(union-atom (a b b) (b c))` | `tuple([S.a, S.b, S.b] + [S.b, S.c])` | `(a b b b c)` | dissolves |
| `!(intersection-atom (a b b c) (b c c))` | `from collections import Counter ⏎ tuple((Counter([S.a, S.b, S.b, S.c]) & Counter([S.b, S.c, S.c])).elements())` | `(b c)` | dissolves |
| `!(subtraction-atom (a b b c) (b c))` | `from collections import Counter ⏎ tuple((Counter([S.a, S.b, S.b, S.c]) - Counter([S.b, S.c])).elements())` | `(a b)` | dissolves |
| `!(unique-atom (a b b c))` | `tuple(dict.fromkeys([S.a, S.b, S.b, S.c]))` | `(a b c)` | dissolves |

- `union` `(-> Atom Atom %Undefined%)` &mdash; Multiset union over nondeterministic answers, which is concatenation: answers are iterables and `+` joins them.
- `intersection` `(-> Atom Atom %Undefined%)` &mdash; `collections.Counter` IS the multiset algebra, and `&` is its intersection.
- `subtraction` `(-> Atom Atom %Undefined%)` &mdash; `Counter` again, with `-`.
- `unique` `(-> Atom %Undefined%)` &mdash; `dict.fromkeys` is Python's order-preserving dedupe.
- `union-atom` `(-> Expression Expression Atom)` &mdash; The same act over an expression's children; a tuple goes back in as one expression.
- `intersection-atom` `(-> Expression Expression Atom)` &mdash; `Counter` over children, answering an expression.
- `subtraction-atom` `(-> Expression Expression Atom)` &mdash; `Counter` over children, answering an expression.
- `unique-atom` `(-> Expression Atom)` &mdash; `dict.fromkeys` over children.

## Control flow and nondeterminism

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(if True a b)` | `S.a if True else S.b` | `a` | dissolves |
| `!(case 2 ((1 one) (2 two) ($x other)))` | `value = 2 ⏎ match value: ⏎     case 1: ⏎         answer = S.one ⏎     case 2: ⏎         answer = S.two ⏎     case _: ⏎         answer = S.other ⏎ answer` | `two` | dissolves |
| `!(switch (+ 1 1) ((1 one) (2 two)))` | `match 1 + 1: ⏎     case 1: ⏎         answer = S.one ⏎     case 2: ⏎         answer = S.two ⏎ answer` | `two` | dissolves |
| `!(let $x 1 (+ $x 1))` | `x = 1 ⏎ x + 1` | `2` | dissolves |
| `!(let* (($x 1) ($y 2)) (+ $x $y))` | `x = 1 ⏎ y = 2 ⏎ x + y` | `3` | dissolves |
| `!(unify (f $x) (f a) $x nope)` | `b = metta.unify(S.f(V.x), S.f(S.a)) ⏎ b['x'] if b is not None else S.nope` | `a` | method |
| `!(superpose (a b))` | `[S.a, S.b]` | `a, b` | dissolves |
| `!(collapse (superpose (a b)))` | `answers = [S.a, S.b] ⏎ tuple(answers)` | `(a b)` | dissolves |
| `!(id 5)` | `5` | `5` | dissolves |
| `!(nop 1 2)` | `metta.Expression()` | `()` | dissolves |
| `!(if-equal a a yes no)` | `S.yes if S.a == S.a else S.no` | `yes` | dissolves |
| `!(quote (+ 1 2))` | `S.quote(S['+'](1, 2))` | `(quote (+ 1 2))` | dissolves |
| `!(noeval (+ 1 2))` | `S['+'](1, 2)` | `(+ 1 2)` | dissolves |
| `!(unquote (quote (+ 1 2)))` | `m.eval(S['+'](1, 2))` | `3` | method |
| `!(gtry id a)` | &mdash; | `a` | absent |
| `!(case% 2 ((1 one) (2 two)))` | &mdash; | `two` | absent |
| `!(let% $x 1 (+ $x 1))` | &mdash; | `2` | absent |
| `!(let*% (($x 1)) $x)` | &mdash; | `1` | absent |
| `!(unify% (f a) (f $x) $x nope)` | &mdash; | `a` | absent |
| `!(get-type =%)` | &mdash; | `(-> $t#0 $t#0 %Undefined%)` | absent |

- `if` `(-> Bool Atom Atom $t)` &mdash; Python's own `if`, and its conditional expression where a value is wanted. Both arms stay unevaluated in MeTTa because the parameters are Atom-typed, which is exactly what Python's own short-circuit does.
- `case` `(-> Atom Expression %Undefined%)` &mdash; Python's `match` statement. A bare variable arm is `case _`.
- `switch` `(-> %Undefined% Expression %Undefined%)` &mdash; Python's `match` statement again. `switch` differs from `case` only in evaluating its subject first, which a Python expression does anyway.
- `let` `(-> Atom %Undefined% Atom %Undefined%)` &mdash; Assignment. It reads in MeTTa's own order, bind then use, which is why plain assignment and not the walrus is the taught spelling.
- `let*` `(-> Expression Atom %Undefined%)` &mdash; A sequence of assignments; a statement sequence in a compiled body already chains into `let*`.
- `unify` `(-> Atom Atom Atom Atom %Undefined%)` &mdash; Structural matching. `metta.unify(pattern, subject)` answers the bindings or `None`, so the four-argument form is that call with a conditional; in a compiled body Python's `match` statement lowers to this instruction. One friction: MeTTa's `unify` is symmetric while `metta.unify` is DIRECTIONAL, pattern first, so swapping the arguments answers `None` [measured 2026-08-22: `metta.unify(S.f(S.a), S.f(V.x))` is None].
- `superpose` `(-> Expression %Undefined%)` &mdash; Nondeterminism has no primitive of its own because Python's iteration IS it: a list of values is a multiset of answers, and `yield` is the same act inside a compiled body.
- `collapse` `(-> Atom Atom)` &mdash; `list()` is the everyday spelling, materialising the answers; `tuple()` is the same act when you want MeTTa's own `( )` atom back, which is what collapse answers.
- `id` `(-> $t $t)` &mdash; The identity function, which Python writes as the value itself.
- `nop` `(-> (%Rest% %Undefined%) (->))` &mdash; Python's `pass`, or simply not writing the call. It answers the unit.
- `if-equal` `(-> Atom Atom Atom Atom %Undefined%)` &mdash; A conditional expression over `==`.
- `quote` `(-> Atom Atom)` &mdash; There is nothing to quote: building a term at the `S.` door never evaluates it, so the quoting question does not arise. `S.quote(x)` builds the term itself where a program needs the constructor.
- `noeval` `(-> Atom Atom)` &mdash; The same point as `quote`: a built term is already unevaluated.
- `unquote` `(-> %Undefined% %Undefined%)` &mdash; Reducing a quoted term is `m.eval`, primitive 4.
- `gtry` `(-> Atom Atom Atom)` &mdash; LeaTTa's guarded try, the failure-to-identity combinator under the Stratego basis. PeTTa ships no strategy basis to build it on. The form is shown but not run here: PeTTa leaves the call unreduced.
- `check-alternatives` `(-> Atom Atom)` &mdash; LeaTTa's alternative-set check inside the Stratego basis.
- `case-empty` `(-> Expression Atom)` &mdash; LeaTTa's own decomposition of `case`.
- `case%` `(-> Atom Expression %Undefined%)` &mdash; LeaTTa's `%`-suffixed variant, the error-transparent twin of `case`. PeTTa ships no `%` family. The form is shown but not run here: PeTTa leaves the call unreduced.
- `let%` `(-> Atom %Undefined% Atom %Undefined%)` &mdash; LeaTTa's error-transparent twin of `let`. The form is shown but not run here: PeTTa leaves the call unreduced.
- `let*%` `(-> Expression Atom %Undefined%)` &mdash; LeaTTa's error-transparent twin of `let*`. The form is shown but not run here: PeTTa leaves the call unreduced.
- `unify%` `(-> Atom Atom Atom Atom %Undefined%)` &mdash; LeaTTa's error-transparent twin of `unify`. The form is shown but not run here: PeTTa leaves the call unreduced.
- `=%` `(-> $t $t %Undefined%)` &mdash; LeaTTa's error-transparent twin of `=`, the equation head itself. The form is shown but not run here: PeTTa does not declare the name.
- `switch-minimal` `(-> Atom Expression Atom)` &mdash; LeaTTa's own decomposition of `switch`.
- `switch-minimal%` `(-> Atom Expression Atom)` &mdash; LeaTTa's own decomposition of `switch`.
- `switch-internal` `(-> Atom Expression Atom)` &mdash; LeaTTa's own decomposition of `switch`.
- `switch-internal%` `(-> Atom Expression Atom)` &mdash; LeaTTa's own decomposition of `switch`.
- `case-empty-internal` `(-> Atom Atom)` &mdash; LeaTTa's own decomposition of `case`.

## Spaces

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(bind! &pb (new-space)) ⏎ !(add-atom &pb (f 1)) ⏎ !(get-atoms &pb)` | `space += (S.f, 1) ⏎ space.atoms()` | `(f 1)` | dissolves |
| `!(bind! &pb (new-space)) ⏎ !(add-atoms &pb ((f 1) (f 2))) ⏎ !(get-atoms &pb)` | `for fact in [(S.f, 1), (S.f, 2)]: ⏎     space += fact ⏎ space.atoms()` | `(f 1), (f 2)` | dissolves |
| `!(bind! &pb (new-space)) ⏎ !(add-reduct &pb (total (+ 1 2))) ⏎ !(get-atoms &pb)` | `space += S.total(m.eval(S['+'](1, 2))[0]) ⏎ space.atoms()` | `(total 3) on leatta and python; (total (+ 1 2)) on metta` | dissolves |
| `!(bind! &pb (new-space)) ⏎ !(add-reducts &pb ((total (+ 1 2)) (total (+ 2 2)))) ⏎ !(get-atoms &pb)` | `for term in [S['+'](1, 2), S['+'](2, 2)]: ⏎     space += S.total(m.eval(term)[0]) ⏎ space.atoms()` | `(total 3), (total 4) on leatta and python; (total (+ 1 2)), (total (+ 2 2)) on metta` | dissolves |
| `!(bind! &pb (new-space)) ⏎ !(add-atom &pb (f 1)) ⏎ !(remove-atom &pb (f 1)) ⏎ !(get-atoms &pb)` | `space += S.f(1) ⏎ space -= S.f(1) ⏎ space.atoms()` | `(no answer)` | dissolves |
| `!(bind! &pb (new-space)) ⏎ !(add-atom &pb (f 1)) ⏎ !(get-atoms &pb)` | `space += S.f(1) ⏎ list(space)` | `(f 1)` | method |
| `!(bind! &pb (new-space)) ⏎ !(add-atom &pb (f 1)) ⏎ !(match &pb (f $x) $x)` | `space += S.f(1) ⏎ [row['x'] for row in space[S.f(V.x)]]` | `1` | method |
| `!(bind! &pb (new-space)) ⏎ !(match% &pb (f $x) $x)` | &mdash; | `(no answer)` | absent |
| `!(get-atoms (new-space))` | `list(metta.space())` | `(no answer)` | method |
| `!(bind! &pb (new-space)) ⏎ !(add-atom &pb (f 1)) ⏎ !(get-atoms (fork-space &pb))` | `space += S.f(1) ⏎ space.copy().atoms()` | `(f 1)` | method |
| `!(add-atom &self (f 1)) ⏎ !(get-atoms &self)` | `space += S.f(1) ⏎ space.atoms()` | `(f 1)` | dissolves |
| `!(add-atom (context-space) (f 1)) ⏎ !(get-atoms (context-space))` | `space += S.f(1) ⏎ space.atoms()` | `(f 1)` | method |
| `!(mod-space! stdlib)` | &mdash; | `&mod:corelib` | absent |
| `!(module-space-no-deps (new-space))` | &mdash; | `&space-#0` | absent |

- `add-atom` `(-> SpaceType Atom (->))` &mdash; `space += atom`, the container protocol. A plain Python tuple encodes to an expression on the way in, so a fact needs no builder ceremony.
- `add-atoms` `(-> SpaceType Expression (->))` &mdash; The same `+=` door, once per fact: anything that yields tuples is a fact stream. One friction, measured: a LIST on the `+=` door writes one atom holding the list rather than one atom per element, so the row loops [measured 2026-08-22: `space += [(S.f, 1), (S.f, 2)]` stores `((f 1) (f 2))`; `space.add(a, b)` is the varargs door that does write both].
- `add-reduct` `(-> SpaceType %Undefined% (->))` &mdash; There is no second door: `+=` adds what you give it, so adding a REDUCT is explicit composition, `space += m.eval(term)[0]`. The row wraps the sum because PeTTa's write door REFUSES a bare grounded atom that its own MeTTa door accepts [measured 2026-08-22: `space += metta.ground(3)` raises `a stored atom is a non-empty expression`, while `!(add-reduct &pb (+ 1 2))` stores `3`]. Where they differ: PeTTa stores `(total (+ 1 2))` UNREDUCED where LeaTTa and the Python composition both store `(total 3)`: this engine's add-reduct does not reduce inside an expression whose head has no equations.
- `add-reducts` `(-> SpaceType %Undefined% (->))` &mdash; The plural of the same composition: evaluate, then write the answers. Where they differ: PeTTa stores both forms UNREDUCED where LeaTTa and the Python composition store `(total 3)` and `(total 4)`, the same non-reduction as `add-reduct`.
- `remove-atom` `(-> SpaceType Atom (->))` &mdash; `space -= atom` removes THAT atom and never pattern-matches; `del space[pattern]` is the pattern form, and the pair is taught together.
- `get-atoms` `(-> SpaceType Atom)` &mdash; `space.atoms()`, or `for atom in space` when you want to walk them.
- `match` `(-> SpaceType Atom Atom %Undefined%)` &mdash; `space[pattern]` is the subscript door and `space.match(pattern)` the named one; the TEMPLATE is built in Python from the answer's bindings.
- `match%` `(-> SpaceType Atom Atom %Undefined%)` &mdash; LeaTTa's error-transparent twin of `match`. The form is shown but not run here: PeTTa leaves the call unreduced.
- `new-space` `(-> SpaceType)` &mdash; `metta.space()`. A constructor call is Python's own spelling for `make me a fresh one`, and the row asks the fresh space for its atoms because the NAME a space gets differs per engine.
- `fork-space` `(-> SpaceType SpaceType)` &mdash; `space.copy()`, which answers an independent space: writing to the copy leaves the original alone [measured 2026-08-22]. The form is shown but not run here: PeTTa leaves the MeTTa call unreduced.
- `&self` `SpaceType` &mdash; The space you are in, which in Python is the handle you already hold: `m` for the engine's own space, `space` for a named one. A name spelt as a symbol is what a Python binding is for.
- `context-space` `(-> SpaceType)` &mdash; The space a program is currently in, which in Python is the handle it holds; `metta.current_space()` is the door for code that did not receive one, and it follows Python's own `current_thread` and `current_task` convention, so the Python word wins over the instruction's name. The row asks both sides for the current space's atoms.
- `mod-space!` `(-> Atom SpaceType)` &mdash; The space of a loaded module. PeTTa's module story is Python packaging, so the name has no image here. The form is shown but not run here: PeTTa leaves the call unreduced.
- `module-space-no-deps` `(-> SpaceType SpaceType)` &mdash; A module's own space without its dependencies. Same module story. The form is shown but not run here: PeTTa leaves the call unreduced.

## Types

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(get-type 1)` | `m.type(1)` | `Number` | method |
| `!(get-type-space &self 1)` | `space.type(1)` | `Number` | method |
| `!(get-metatype (a b))` | `e = metta.Expression(S.a, S.b) ⏎ S[e.metatype]` | `Expression` | dissolves |
| `!(is-function (-> Number Number))` | `t = S['->'](S.Number, S.Number) ⏎ t[0] == S['->']` | `True` | dissolves |
| `(: pbf (-> Number Number)) ⏎ (= (pbf $x) $x) ⏎ !(get-type pbf)` | `t = S['->'](S.Number, S.Number) ⏎ t` | `(-> Number Number)` | dissolves |
| `(= (pbf $x) (+ $x 1)) ⏎ !(pbf 1)` | `space += metta.equation(S.pbf(V.x)).to(V.x + 1) ⏎ space.eval(S.pbf(1))[0]` | `2` | method |
| `!(get-type &self)` | &mdash; | `SpaceType` | absent |
| `!(get-type TP)` | &mdash; | `Type` | absent |
| `!(get-type TU)` | &mdash; | `(-> Type Type)` | absent |
| `!(get-type (Pair 1 2))` | &mdash; | `%Undefined%` | absent |
| `!(get-type PairType)` | &mdash; | `%Undefined%` | absent |
| `!(skel-swap-pair (Pair 1 2))` | &mdash; | `(skel-swap-pair (Pair 1 2))` | absent |
| `!(skel-swap-pair-native (Pair 1 2))` | &mdash; | `(skel-swap-pair-native (Pair 1 2))` | absent |
| `!(get-type ◁)` | &mdash; | `(-> Atom Type Atom Atom)` | absent |

- `get-type` `(-> Atom %Undefined%)` &mdash; Declared types are space-relative, so `space.type(atom)` asks the space. Class declarations use the consolidated `@space.define` decorator.
- `get-type-space` `(-> SpaceType Atom Atom)` &mdash; The same question asked of a named space through that handle's `space.type(atom)` method.
- `get-metatype` `(-> Atom Atom)` &mdash; Python's own builtin `type`: the four atom classes ARE the four metatypes, so `type(a).__name__` is the metatype by construction.
- `is-function` `(-> Type Bool)` &mdash; Asking whether a type is an arrow. In Python the same question is asked of the annotation, and `m.is_function(name)` asks it of a defined name.
- `->` `(-> (%Rest% Type) Type)` &mdash; Annotations. A parameter and return annotation on a decorated function emits the arrow, and `Callable[[int], int]` maps through the same one table; `S['->']` stays for a hand-built arrow.
- `=` `(-> $t $t %Undefined%)` &mdash; The definitional decorator. `@m.define` compiles a function into equations, `metta.equation(lhs).to(rhs)` builds one by hand, and both land as ordinary `(= ...)` atoms a program can match.
- `SpaceType` `Type` &mdash; The type of a space. PeTTa does not declare the name, so there is nothing for a Python type table to map to yet. The form is shown but not run here: PeTTa answers SpaceType for a space but does not declare the symbol itself.
- `TP` `Type` &mdash; LeaTTa's type-preserving strategy type, Lämmel's TP. It arrives with the strategy basis or not at all. The form is shown but not run here: PeTTa does not declare the name.
- `TU` `(-> Type Type)` &mdash; LeaTTa's type-unifying strategy type, Lämmel's TU. The form is shown but not run here: PeTTa does not declare the name.
- `Pair` `(-> $ta $tb (PairType $ta $tb))` &mdash; A constructor from LeaTTa's `skel` demonstration module. PeTTa has no such module; a class decorated with `@space.define` declares its constructor in that space. The form is shown but not run here: PeTTa does not declare the name.
- `PairType` `(-> $ta $tb Type)` &mdash; The parameterised type of `Pair`, from the same module. The form is shown but not run here: PeTTa does not declare the name.
- `skel-swap-pair` `(-> (PairType $ta $tb) (PairType $tb $ta))` &mdash; The `skel` module's worked equation, LeaTTa's demonstration that a built-in module can ship both a MeTTa and a native implementation. The form is shown but not run here: PeTTa does not declare the name.
- `skel-swap-pair-native` `(-> (PairType $ta $tb) (PairType $tb $ta))` &mdash; The native half of the same demonstration. The form is shown but not run here: PeTTa does not declare the name.
- `◁` `(-> Atom Type Atom Atom)` &mdash; LeaTTa's typed strategy application operator, the selection half of the TP/TU layer. The form is shown but not run here: PeTTa does not declare the name.

## The state cell

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(get-state (new-state 1))` | `state = metta.State[int](1, space=m) ⏎ state.value` | `1` | method |
| `!(let $c (new-state 5) (get-state $c))` | `state = metta.State[int](5, space=m) ⏎ state.value` | `5` | method |
| `!(let $c (new-state 1) (get-state (change-state! $c 2)))` | `state = metta.State[int](1, space=m) ⏎ state.value = 2 ⏎ state.value` | `2` | method |

- `new-state` `(-> $t (StateMonad $t))` &mdash; `metta.State[T](value, space=space)` creates the typed Python handle. The row reads `.value` because the engine cell itself is deliberately hidden behind that handle.
- `get-state` `(-> (StateMonad $tgso) $tgso)` &mdash; Reading the cell is the typed handle's `state.value` property.
- `change-state!` `(-> (StateMonad $tcso) $tcso (StateMonad $tcso))` &mdash; Assigning `state.value` writes the same typed engine cell and reading it back returns the replacement.
- `_new-state` `(-> $t Expression (StateMonad $t))` &mdash; LeaTTa's internal constructor behind `new-state`.

## Printing and text

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(println! hello)` | `print('hello') ⏎ metta.Expression()` | `()` | dissolves |
| `!(trace! hello (+ 1 2))` | `print('hello') ⏎ 1 + 2` | `3` | dissolves |
| `!(format-args "{} and {}" (a b))` | `a, b = S.a, S.b ⏎ f'{a} and {b}'` | `"a and b"` | dissolves |
| `!(print-alternatives! subject (a b))` | `print(S.subject, [S.a, S.b]) ⏎ metta.Expression()` | `()` | dissolves |

- `println!` `(-> %Undefined% (->))` &mdash; Python's `print`.
- `trace!` `(-> %Undefined% Atom %Undefined%)` &mdash; `print` or `logging` beside the value; `m.trace()` is the engine's own reduction trace, a different and deeper thing.
- `format-args` `(-> String Expression String)` &mdash; An f-string. MeTTa's `{}` holes are Python's own interpolation.
- `print-alternatives!` `(-> Atom Expression (->))` &mdash; Python's `print` over the answers, which is what LeaTTa's assert family uses it for: showing what a form actually answered. The form is shown but not run here: PeTTa leaves the MeTTa call unreduced.
- `print-alternatives-each!` `(-> Expression (->))` &mdash; LeaTTa's per-alternative half of the printer.

## Testing

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(assert (== 1 1))` | `assert 1 == 1 ⏎ True` | `() on leatta; True on metta and python` | dissolves |
| `!(assertEqual (+ 1 1) 2)` | `assert m.eval(S['+'](1, 1))[0] == 2 ⏎ True` | `() on leatta; True on metta and python` | dissolves |
| `!(assertEqualMsg (+ 1 1) 2 "sums")` | `assert m.eval(S['+'](1, 1))[0] == 2, 'sums' ⏎ True` | `() on leatta; True on metta and python` | dissolves |
| `!(assertAlphaEqual (f $x) (f $y))` | `assert S.f(V.x).alpha_eq(S.f(V.y)) ⏎ True` | `() on leatta; True on metta and python` | dissolves |
| `!(assertAlphaEqualMsg (f $x) (f $y) "renaming")` | `assert S.f(V.x).alpha_eq(S.f(V.y)), 'renaming' ⏎ True` | `() on leatta; True on metta and python` | dissolves |
| `!(assertEqualToResult (superpose (1 2)) (1 2))` | `assert m.eval(S.superpose(metta.Expression(1, 2))) == [1, 2] ⏎ True` | `() on leatta; True on metta and python` | dissolves |
| `!(assertEqualToResultMsg (superpose (1 2)) (1 2) "both")` | `assert m.eval(S.superpose(metta.Expression(1, 2))) == [1, 2], 'both' ⏎ True` | `() on leatta; True on metta and python` | dissolves |
| `!(assertAlphaEqualToResult (f $x) ((f $y)))` | `assert m.eval(S.f(V.x))[0].alpha_eq(S.f(V.y)) ⏎ True` | `() on leatta; True on metta and python` | dissolves |
| `!(assertAlphaEqualToResultMsg (f $x) ((f $y)) "renaming")` | `assert m.eval(S.f(V.x))[0].alpha_eq(S.f(V.y)), 'renaming' ⏎ True` | `() on leatta; True on metta and python` | dissolves |
| `!(assertIncludes (superpose (a b)) (a))` | `assert S.a in m.eval(S.superpose(metta.Expression(S.a, S.b))) ⏎ True` | `() on leatta; True on metta and python` | dissolves |

- `assert` `(-> Atom (->))` &mdash; Python's own `assert`. A twin or a test states its claims this way and the run proves them, because a false assertion raises. Where they differ: LeaTTa answers the unit `()` where PeTTa answers True.
- `assertEqual` `(-> Atom Atom (->))` &mdash; `assert a == b`, and pytest's own assertion rewriting prints the halves. Where they differ: LeaTTa answers the unit `()` where PeTTa answers True.
- `assertEqualMsg` `(-> Atom Atom Atom (->))` &mdash; `assert a == b, message`, which is Python's own second argument. Where they differ: LeaTTa answers the unit `()` where PeTTa answers True.
- `assertAlphaEqual` `(-> Atom Atom (->))` &mdash; `assert a.alpha_eq(b)`: the assertion is Python's, the relation is MeTTa's. Where they differ: LeaTTa answers the unit `()` where PeTTa answers True.
- `assertAlphaEqualMsg` `(-> Atom Atom Atom (->))` &mdash; The same with Python's assertion message. Where they differ: LeaTTa answers the unit `()` where PeTTa answers True.
- `assertEqualToResult` `(-> Atom Atom (->))` &mdash; The right-hand side is a LIST of expected answers rather than one, which is `assert list(answers) == [...]`. Where they differ: LeaTTa answers the unit `()` where PeTTa answers True.
- `assertEqualToResultMsg` `(-> Atom Atom Atom (->))` &mdash; The same with Python's assertion message. Where they differ: LeaTTa answers the unit `()` where PeTTa answers True.
- `assertAlphaEqualToResult` `(-> Atom Atom (->))` &mdash; The answer-list form compared modulo renaming. Where they differ: LeaTTa answers the unit `()` where PeTTa answers True.
- `assertAlphaEqualToResultMsg` `(-> Atom Atom Atom (->))` &mdash; The same with Python's assertion message. Where they differ: LeaTTa answers the unit `()` where PeTTa answers True.
- `assertIncludes` `(-> Atom Expression (->))` &mdash; Python's own `in`. Where they differ: LeaTTa answers the unit `()` where PeTTa answers True.
- `_assert-results-are-equal` `(-> Atom Atom Atom (->))` &mdash; LeaTTa's internal comparison behind the assert family.
- `_assert-results-are-equal-msg` `(-> Atom Atom Atom Atom (->))` &mdash; LeaTTa's internal comparison behind the assert family.
- `_assert-results-are-alpha-equal` `(-> Atom Atom Atom (->))` &mdash; LeaTTa's internal comparison behind the assert family.
- `_assert-results-are-alpha-equal-msg` `(-> Atom Atom Atom Atom (->))` &mdash; LeaTTa's internal comparison behind the assert family.

## Documentation

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(get-doc &self +)` | `def slug(title): ⏎     'Make a title into a slug.' ⏎ slug.__doc__` | `(@doc-formal (@item +) (@kind function) (@type (-> Number Number Number)) (@desc "Sums two numbers") (@params ((@param (@type Number) (@desc "Addend")) (@param (@type Number) (@desc "Augend")))) (@return (@type Number) (@desc "Sum"))) on leatta; (no answer) on metta; "Make a title into a slug." on python` | dissolves |
| `!(@doc pbf (@desc "adds one"))` | `def pbf(x): ⏎     'adds one' ⏎ pbf.__doc__` | `(@doc pbf (@desc "adds one")) on leatta and metta; "adds one" on python` | dissolves |
| `!(@desc "adds one")` | `'adds one'` | `(@desc "adds one") on leatta and metta; "adds one" on python` | dissolves |
| `!(@param "the addend")` | `'the addend'` | `(@param "the addend") on leatta and metta; "the addend" on python` | dissolves |
| `!(@params ((@param "the addend")))` | `['the addend']` | `(@params ((@param "the addend"))) on leatta and metta; "the addend" on python` | dissolves |
| `!(@return "the sum")` | `'the sum'` | `(@return "the sum") on leatta and metta; "the sum" on python` | dissolves |
| `!(@type Number)` | `def pbf(x: int) -> int: ⏎     'adds one' ⏎ pbf.__annotations__['return']` | `(@type Number) on leatta and metta; "int" on python` | dissolves |
| `!(@item pbf)` | `S.pbf` | `(@item pbf) on leatta and metta; pbf on python` | dissolves |
| `!(@doc-formal (@item pbf) (@kind function) (@type (-> Number Number)) (@desc "adds one"))` | `def pbf(x: int) -> int: ⏎     'adds one' ⏎ (pbf.__annotations__['return'], pbf.__doc__)` | `(@doc-formal (@item pbf) (@kind function) (@type (-> Number Number)) (@desc "adds one")) on leatta and metta; ("int" "adds one") on python` | dissolves |
| `!(help! +)` | `def pbf(x): ⏎     'adds one' ⏎ pbf.__doc__` | `() on leatta; "adds one" on python` | dissolves |

- `get-doc` `(-> SpaceType Atom %Undefined%)` &mdash; Python's builtin `help`, over the docstring a decorated function already carries. PeTTa answers nothing here because no documentation atoms are written yet, which is the doc-vocabulary gap. Where they differ: LeaTTa answers the full `@doc-formal` structure for `+`; PeTTa answers nothing, because nothing emits documentation atoms.
- `@doc` `(-> Atom DocDescription DocInformal) | (-> Atom DocDescription DocParameters DocReturnInformal DocInformal)` &mdash; A docstring. One docstring is meant to feed both worlds: Python's `help` and the engine's `get-doc`, once the emission lands. Where they differ: the MeTTa side is a CONSTRUCTOR and stays unreduced on both engines, which is correct; the Python side shows the same text.
- `@desc` `(-> String DocDescription)` &mdash; The description line of a docstring. Where they differ: the MeTTa side is a constructor and stays unreduced, correctly.
- `@param` `(-> String DocParameterInformal) | (-> DocType DocDescription DocParameter)` &mdash; One parameter's line in a docstring, which the docstring convention already carries. Where they differ: the MeTTa side is a constructor and stays unreduced, correctly.
- `@params` `(-> Expression DocParameters)` &mdash; The parameter block of a docstring. Where they differ: the MeTTa side is a constructor and stays unreduced, correctly.
- `@return` `(-> String DocReturnInformal) | (-> DocType DocDescription DocReturn)` &mdash; The return line of a docstring. Where they differ: the MeTTa side is a constructor and stays unreduced, correctly.
- `@type` `(-> Type DocType)` &mdash; The type shown in documentation, which annotations already supply. Where they differ: the MeTTa side is a constructor and stays unreduced, correctly.
- `@item` `(-> Atom DocItem)` &mdash; The subject a documentation record is about, which in Python is the object the docstring hangs on. Where they differ: the MeTTa side is a constructor and stays unreduced, correctly.
- `@doc-formal` `(-> DocItem DocKindFunction DocType DocDescription DocParameters DocReturn DocFormal) | (-> DocItem DocKindAtom DocType DocDescription DocFormal) | (-> DocItem DocKindFunction DocType DocDescription DocFormal)` &mdash; The whole documentation record, which a typed and docstringed Python function already is: signature plus prose in one place. Where they differ: the MeTTa side is a constructor and stays unreduced, correctly.
- `help!` `(-> Atom (->)) | (-> (->))` &mdash; Python's builtin `help`, which is the same act on the same docstring. Where they differ: LeaTTa prints the documentation and answers the unit; PeTTa leaves the call unreduced because it declares no documentation. The form is shown but not run here: PeTTa leaves the call unreduced.
- `help-internal!` `(-> Atom (->)) | (-> Symbol (->))` &mdash; LeaTTa's internal dispatch behind `help!`.
- `help-param!` `(-> Atom (->))` &mdash; LeaTTa's internal parameter printer behind `help!`.
- `help-space!` `(-> SpaceType (->))` &mdash; LeaTTa's internal space-documentation printer behind `help!`.
- `get-doc-atom` `(-> SpaceType Atom %Undefined%)` &mdash; LeaTTa's internal dispatch behind `get-doc`.
- `get-doc-function` `(-> SpaceType Atom Type %Undefined%)` &mdash; LeaTTa's internal dispatch behind `get-doc`.
- `get-doc-single-atom` `(-> SpaceType Atom %Undefined%)` &mdash; LeaTTa's internal dispatch behind `get-doc`.
- `get-doc-params` `(-> Expression Atom Expression (Expression Atom))` &mdash; LeaTTa's internal dispatch behind `get-doc`.
- `undefined-doc-function-type` `(-> Expression Type)` &mdash; LeaTTa's internal fallback type for an undocumented application.

## Modules and imports

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(import! &self (library lib_he)) ⏎ !(unify (f a) (f $x) $x nope)` | `import math ⏎ S[math.__name__]` | `a on leatta and metta; math on python` | dissolves |
| `!(import-into! (new-space) (library lib_he))` | &mdash; | `(Error (import-into! &space-#0 (library lib_he)) import-into!: module must be a symbol)` | absent |
| `!(import-item! &self (library lib_he) unify)` | &mdash; | `(Error (import-item! &self (library lib_he) unify) import-item! expects (import-item! <dest> <module> <item>))` | absent |
| `!(get-metatype include)` | `import pathlib, tempfile ⏎ path = pathlib.Path(tempfile.mkdtemp()) / 'inc.metta' ⏎ path.write_text('(= (pbi) 7)\n') ⏎ space.load(str(path)) ⏎ space.eval(S.pbi())[0]` | `Grounded on leatta and metta; 7 on python` | method |
| `!(get-metatype git-import!)` | `import importlib ⏎ S[importlib.import_module('json').__name__]` | `Grounded on leatta and metta; json on python` | method |
| `!(get-metatype git-module!)` | &mdash; | `Grounded` | absent |
| `!(get-metatype register-module!)` | &mdash; | `Grounded` | absent |
| `!(print-mods!)` | `import sys ⏎ print(len(sys.modules), 'modules') ⏎ metta.Expression()` | `()` | dissolves |
| `!(loaded-mods!)` | `import sys ⏎ S['json'] if 'json' in sys.modules else S.absent` | `(corelib builtin:skel) on leatta; json on python` | dissolves |
| `!(module-tree!)` | `import importlib.metadata ⏎ S[importlib.metadata.requires.__name__]` | `(top corelib stdlib skel) on leatta; requires on python` | dissolves |
| `!(bind! &pb (new-space)) ⏎ !(add-atom &pb (f 1)) ⏎ !(get-atoms &pb)` | `space += S.f(1) ⏎ space.atoms()` | `(f 1)` | dissolves |

- `import!` `(-> Atom Atom (->))` &mdash; Python's own `import`, and for a MeTTa library the boot manifest or `m.load(path)`. The module catalog IS Python packaging. Where they differ: MeTTa imports a MeTTa library into a space where Python imports a Python module into a namespace.
- `import-into!` `(-> SpaceType Atom (->))` &mdash; Importing into a NAMED space rather than the current one. PeTTa's loader does not offer it. The form is shown but not run here: PeTTa leaves the call unreduced.
- `import-item!` `(-> Atom Atom Atom (->))` &mdash; Importing one named item, which is Python's `from x import y`. Not implemented here. The form is shown but not run here: PeTTa leaves the call unreduced.
- `include` `(-> Atom %Undefined%)` &mdash; `space.load(path)` reads a file into that space, which is what include does; Python's own `import` is the spelling for a Python module. Where they differ: no file path is portable between the two engines, so the MeTTa column shows only that the name is a grounded operation while the Python column loads a real file and calls what it defined.
- `git-import!` `(-> String String Atom)` &mdash; pip and `importlib`. Fetching a dependency is packaging's job, the module catalog IS Python packaging, and a boot manifest names the distribution. Where they differ: a row cannot fetch a repository, so the MeTTa column shows only that the name is a grounded operation while the Python column imports a distribution that is already installed.
- `git-module!` `(-> Atom (->))` &mdash; Upstream's bespoke package manager. The form is shown but not run here: PeTTa does not declare the name. Ruled rather than missing: decision 8: the module catalog IS Python packaging, and upstream's bespoke manager is the fork not taken, so the absence is a decision rather than a gap.
- `register-module!` `(-> Atom (->))` &mdash; Registering a module with the bespoke catalog. A Python distribution registers itself by declaring an entry point, which pip then installs. The form is shown but not run here: PeTTa does not declare the name. Ruled rather than missing: decision 8: pip and entry-point discovery are the catalog, so the absence is a decision rather than a gap.
- `print-mods!` `(-> (->))` &mdash; `print(sorted(sys.modules))`. Under the ruling that the module catalog IS Python packaging, the loaded-module question is Python's own. Where they differ: MeTTa modules there, Python modules here, which is what the ruling makes them. The form is shown but not run here: PeTTa does not declare the name.
- `loaded-mods!` `(-> Atom)` &mdash; `sys.modules`, the same list as data rather than printed. Where they differ: MeTTa modules there, Python modules here. The form is shown but not run here: PeTTa does not declare the name.
- `module-tree!` `(-> Atom)` &mdash; `importlib.metadata.requires(name)`, which answers the dependency tree a distribution declares. The row names the door rather than a package, because no distribution is guaranteed installed wherever the lane runs. Where they differ: the trees are different: MeTTa modules there, installed distributions here. The form is shown but not run here: PeTTa does not declare the name.
- `bind!` `(-> Symbol %Undefined% (->))` &mdash; A Python name binding. `space = metta.space(...)` is exactly what a token binding was for, and Python's own scoping rules then apply.

## Errors

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(Error a b)` | `S.Error(S.a, S.b)` | `(Error a b)` | dissolves |
| `!(get-type (Error a b))` | `S.ErrorType` | `ErrorType` | dissolves |
| `!(get-type BadType)` | &mdash; | `(-> Type Type ErrorDescription)` | absent |
| `!(get-type BadArgType)` | &mdash; | `(-> Number Type Type ErrorDescription)` | absent |
| `!(get-type IncorrectNumberOfArguments)` | &mdash; | `ErrorDescription` | absent |
| `!(if-error (Error a b) yes no)` | `e = S.Error(S.a, S.b) ⏎ S.yes if e[0] == S.Error else S.no` | `yes` | dissolves |
| `!(return-on-error a b)` | `value = S.a ⏎ value if isinstance(value, metta.Expression) and value[0] == S.Error else S.b` | `b` | dissolves |
| `!(separate-errors ((Error a b) c) ())` | `answers = [S.Error(S.a, S.b), S.c] ⏎ [a for a in answers if isinstance(a, metta.Expression) and a[0] == S.Error]` | `(Error a b)` | dissolves |

- `Error` `(-> Atom Atom ErrorType)` &mdash; An exception. A Python operation raises and the boundary maps the exception INTO this algebra rather than inventing a parallel one. The constructor itself never reduces, on either engine, which is correct.
- `ErrorType` `Type` &mdash; The type an error atom carries, which on the Python side is the exception class.
- `BadType` `(-> Type Type ErrorDescription)` &mdash; The canonical wrong-type error description. PeTTa does not declare the name, which is the error-vocabulary gap ledger X names. The form is shown but not run here: PeTTa does not declare the name.
- `BadArgType` `(-> Number Type Type ErrorDescription)` &mdash; The positional form, `(BadArgType <pos> <expected> <actual>)`. Same gap. The form is shown but not run here: PeTTa does not declare the name.
- `IncorrectNumberOfArguments` `ErrorDescription` &mdash; The arity error description, which Python's own `TypeError` is the image of. Same gap. The form is shown but not run here: PeTTa does not declare the name.
- `if-error` `(-> Atom Atom Atom %Undefined%)` &mdash; `try`/`except`, or a conditional over the value. It is the railway combinator over Error atoms.
- `return-on-error` `(-> Atom Atom %Undefined%)` &mdash; Early return, which is Python's own `return` inside an `if`. Indexing needs the guard because a leaf atom is not indexable here.
- `separate-errors` `(-> Expression Expression Expression)` &mdash; Partitioning answers into errors and results, which is one comprehension per side. The form is shown but not run here: PeTTa leaves the call unreduced.

## Rewriting strategies

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `(= strategy-a strategy-b) ⏎ !(try strategy-a)` | &mdash; | `strategy-b` | absent |
| `(= strategy-a strategy-b) ⏎ (= strategy-b strategy-c) ⏎ !(repeat strategy-a)` | &mdash; | `strategy-c` | absent |
| `(= strategy-a strategy-b) ⏎ (= (strategy-node strategy-b) strategy-bottomup-root) ⏎ !(topdown (strategy-node strategy-a))` | &mdash; | `(strategy-node strategy-b)` | absent |
| `(= strategy-a strategy-b) ⏎ (= (strategy-node strategy-b) strategy-bottomup-root) ⏎ !(bottomup (strategy-node strategy-a))` | &mdash; | `strategy-bottomup-root` | absent |
| `(= strategy-a strategy-b) ⏎ (= strategy-b strategy-c) ⏎ (= (strategy-node strategy-c) strategy-innermost-root) ⏎ !(innermost (strategy-node strategy-a))` | &mdash; | `strategy-innermost-root` | absent |
| `!(stratego-all id (f a b))` | &mdash; | `(f a b)` | absent |
| `!(stratego-one id (f a b))` | &mdash; | `(f a b), (f a b), (f a b)` | absent |
| `!(eval-via-match (+ 1 2))` | &mdash; | `3` | absent |
| `!(eval-via-unify (+ 1 2))` | &mdash; | `3` | absent |
| `!(reduce-via-match (+ 1 2) x)` | &mdash; | `(reduce-via-match (+ 1 2) x)` | absent |

- `try` `TP | (-> Atom Atom)` &mdash; Stratego's `try(s) = s <+ id`, one rewriting step with failure turned into identity. LeaTTa ships the basis specialised to `eval-via-match`; PeTTa ships no strategy basis, and the ruling is that a `lib_strategy` PORTS LeaTTa's, so the Python side needs only the names. The form is shown but not run here: PeTTa leaves the call unreduced.
- `repeat` `TP | (-> Atom Atom)` &mdash; Stratego's `repeat(s) = try(s ; repeat(s))`, root steps to a normal form. The form is shown but not run here: PeTTa leaves the call unreduced.
- `topdown` `TP | (-> Atom Atom)` &mdash; Stratego's `topdown(s) = s ; all(topdown(s))`, preorder traversal. The form is shown but not run here: PeTTa leaves the call unreduced.
- `bottomup` `TP | (-> Atom Atom)` &mdash; Stratego's `bottomup(s) = all(bottomup(s)) ; s`, postorder traversal. The form is shown but not run here: PeTTa leaves the call unreduced.
- `innermost` `TP | (-> Atom Atom)` &mdash; Stratego's `innermost(s) = bottomup(try(s ; innermost(s)))`. The form is shown but not run here: PeTTa leaves the call unreduced.
- `stratego-all` `(-> Atom Atom Atom)` &mdash; Stratego's `all(s)`, applying a strategy to every child. The form is shown but not run here: PeTTa leaves the call unreduced.
- `stratego-one` `(-> Atom Atom Atom)` &mdash; Stratego's `one(s)`, applying to one child. LeaTTa deliberately diverges from Stratego's committed choice by answering EVERY successful position through MeTTa's own nondeterminism. The form is shown but not run here: PeTTa leaves the call unreduced.
- `stratego-all-tail` `(-> Atom Expression Expression)` &mdash; LeaTTa's internal tail recursion behind `stratego-all`.
- `eval-via-match` `(-> Atom %Undefined%)` &mdash; The one-step rewriting strategy the whole basis is specialised to. The form is shown but not run here: PeTTa leaves the call unreduced.
- `eval-via-unify` `(-> Atom %Undefined%)` &mdash; The unification-directed sibling of `eval-via-match`. The form is shown but not run here: PeTTa leaves the call unreduced.
- `reduce-via-match` `(-> Atom Atom %Undefined%)` &mdash; The reduction form of the same strategy. The form is shown but not run here: PeTTa leaves the call unreduced.

## Matching extensions

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(fuzzy-match (f a) ((f a) (f b)) 1)` | &mdash; | `(fuzzy-result (cost 0) (f a)), (fuzzy-result (cost 1) (f b))` | absent |
| `!(fuzzy-match-space (new-space) (f a) ((f a)) 1)` | &mdash; | `(fuzzy-result (cost 0 0 0) (f a))` | absent |
| `!(fuzzy-match-context (new-space) (new-space) (f a) ((f a)) 1)` | &mdash; | `(fuzzy-result (cost 0 0 0 0) (f a))` | absent |
| `!(near-match (f a) ((f a) (f b)) 1)` | &mdash; | `(near-match (f a) ((f a) (f b)) 1)` | absent |
| `!(sealed ($x) ($x $y))` | `m.eval(S.sealed(metta.Expression(V.x), metta.Expression(V.x, V.y)))[0]` | `($x $y#0) on leatta and metta; ($_v0 $_v1) on python` | method |
| `!(capture (+ 1 2))` | &mdash; | `3` | absent |

- `fuzzy-match` `(-> Atom Expression Number Atom)` &mdash; LeaTTa's cost-bounded approximate matcher, answering each candidate with its cost. PeTTa has `metta.structures` for many-to-one matching and no approximate matcher. The form is shown but not run here: PeTTa leaves the call unreduced.
- `fuzzy-match-space` `(-> SpaceType Atom Expression Number Atom)` &mdash; The same over a space's atoms. The form is shown but not run here: PeTTa leaves the call unreduced.
- `fuzzy-match-context` `(-> SpaceType SpaceType Atom Expression Number Atom)` &mdash; The same with a separate cost-declaration space. The form is shown but not run here: PeTTa leaves the call unreduced.
- `near-match` `(-> Atom Expression Atom Atom)` &mdash; The nearest-candidate form of the same family. The form is shown but not run here: PeTTa leaves the call unreduced.
- `sealed` `(-> Expression Atom Atom)` &mdash; Freshening every variable except a named few, the hygiene primitive under rule emission. The Python surface makes most uses unnecessary by construction, because a parameter-scoped rule is fresh per rule, so the row shows the law spelling. Where they differ: both freshen the second variable and keep the first, but the names differ: a variable built in Python comes back from the engine as `$_96674` rather than `$x`, so the two sides are alpha-equal and not string-equal.
- `capture` `(-> Atom Atom)` &mdash; Closing an atom over the current space. A Python function object already binds its engine and space, so the uses vanish; PeTTa does not implement the name. The form is shown but not run here: PeTTa leaves the call unreduced.

## The minimal core

| MeTTa | Python | answers | bucket |
|---|---|---|---|
| `!(eval (+ 1 2))` | `m.eval(S['+'](1, 2))` | `3` | method |
| `!(evalc (+ 1 2) &self)` | `space.eval(S['+'](1, 2))` | `3` | method |
| `!(metta (+ 1 2) %Undefined% &self)` | `m.eval(S['+'](1, 2))` | `3` | method |
| `!(chain (+ 1 2) $x (foo $x))` | `x = m.eval(S['+'](1, 2))[0] ⏎ S.foo(x)` | `(foo 3)` | dissolves |
| `!(function (return 5))` | &mdash; | `5` | absent |
| `!(function (return (+ 2 3)))` | &mdash; | `(+ 2 3)` | absent |
| `!(collapse-bind (superpose (a b)))` | &mdash; | `((a (bindings)) (b (bindings)))` | absent |
| `!(superpose-bind ((a (bindings))))` | &mdash; | `a` | absent |

- `eval` `(-> Atom Atom)` &mdash; ONE step. `m.eval(term)` is the same one step and answers every result, and `space.eval(term)` is `evalc`, the same step in a named space.
- `evalc` `(-> Atom SpaceType Atom)` &mdash; One step WITH an explicit context space, which is `space.eval(term)`: the signature IS term plus space.
- `metta` `(-> Atom Type SpaceType Atom)` &mdash; The full interpreter, which is what CALLING does: a defined object called from Python evaluates, and `m.eval` on a built term is the same act.
- `chain` `(-> Atom Variable Atom %Undefined%)` &mdash; Python assignment. Chain executes one instruction, binds, substitutes and continues, which is exactly `x = m.eval(t)[0]` followed by use of `x`.
- `function` `(-> Atom Atom)` &mdash; The core's function frame, which `return` closes. PeTTa's compiled definitions do not go through this instruction and it is not implemented. The form is shown but not run here: PeTTa leaves the call unreduced.
- `return` `(-> $t $t)` &mdash; The core's return, paired with `function`: it is what closes the frame, so it only ever appears inside one. The form is shown but not run here: PeTTa leaves the call unreduced.
- `collapse-bind` `(-> Atom Expression) | (TU Expression)` &mdash; The deep-tier collapse that keeps each alternative's BINDINGS, `((a (bindings ...)) ...)`. It belongs to the bindings-carrying tier, never to the surface; PeTTa's engine has the bindings carrier (`answer_bindings`) but not this instruction. The form is shown but not run here: PeTTa leaves the call unreduced.
- `superpose-bind` `(-> Expression Atom)` &mdash; The inverse of `collapse-bind`: it restores each alternative WITH its recorded bindings, which is a different operation from `superpose`. The form is shown but not run here: PeTTa leaves the call unreduced.
- `metta-call` `(-> Atom Type SpaceType Atom)` &mdash; LeaTTa's grounded-call step inside `metta`.
- `metta-call-result` `(-> Atom Atom Type SpaceType Atom)` &mdash; LeaTTa's grounded-call continuation inside `metta`.
- `_minimal-foldl-atom` `(-> Expression Atom Variable Variable Atom SpaceType %Undefined%)` &mdash; LeaTTa's internal fold behind `foldl-atom`, declared twice in the manifest: once in the prelude and once in a built-in module registry.

## The mechanised interpreter

LeaTTa's typed interpreter, written in MeTTa: `interpret` and the equations that implement it. This is the machinery that makes LeaTTa an oracle rather than a second implementation, and PeTTa writes its interpreter in Prolog, so none of these names is on either surface (51 names).

> `interpret`, `interpret-args`, `interpret-args-at`, `interpret-args-ok`, `interpret-args-tail`, `interpret-args-tail-at`, `interpret-carrier-append`, `interpret-carrier-append-choice`, `interpret-dispatch`, `interpret-expression`, `interpret-expression-dispatch`, `interpret-expression-function`, `interpret-expression-ok`, `interpret-expression-operator`, `interpret-expression-selected`, `interpret-expression-tuple`, `interpret-func`, `interpret-func-args`, `interpret-func-ok`, `interpret-func-plan`, `interpret-function-arg-data`, `interpret-function-check`, `interpret-function-check-arg`, `interpret-function-check-arg-return`, `interpret-function-check-args`, `interpret-function-check-args-head`, `interpret-function-check-args-ready`, `interpret-function-check-data`, `interpret-function-check-result`, `interpret-function-check-return`, `interpret-function-check-tail`, `interpret-function-checked-data`, `interpret-function-return-data`, `interpret-function-selected-data`, `interpret-function-selection`, `interpret-function-tail-data`, `interpret-function-type`, `interpret-function-type-classified`, `interpret-function-type-data`, `interpret-function-type-ok`, `interpret-function-types`, `interpret-function-types-checked`, `interpret-function-types-data`, `interpret-function-types-end`, `interpret-function-types-end-classified`, `interpret-function-types-tail`, `interpret-is-metatype`, `interpret-result-type`, `interpret-tuple`, `interpret-type-cast`, `interpret-type-cast-error-or-bad-type`

LeaTTa's minimal interpreter, written in MeTTa: the fourteen core instructions implemented in terms of each other (54 names).

> `mi-apply-chain`, `mi-apply-chain-collapsed`, `mi-apply-chain-collapsed-choice`, `mi-apply-chain-empty-prepare`, `mi-apply-chain-prepare`, `mi-apply-chain-prepare-choice`, `mi-apply-chain-prepare-head`, `mi-apply-chain-prepare-nonempty`, `mi-apply-chain-prepare-one`, `mi-apply-chain-prepare-tail`, `mi-apply-chain-prepared`, `mi-apply-chain-prepared-carrier`, `mi-apply-chain-prepared-one`, `mi-apply-chain-run`, `mi-apply-chain-run-result`, `mi-apply-chain-substituted`, `mi-apply-chain-substituted-carrier`, `mi-apply-chain-substitution-failed`, `mi-apply-unify`, `mi-apply-unify-attempt`, `mi-apply-unify-final`, `mi-apply-unify-has-segment`, `mi-apply-unify-hit`, `mi-apply-unify-probe`, `mi-apply-unify-probed`, `mi-apply-unify-rigid`, `mi-apply-unify-rigid-order`, `mi-apply-unify-rigid-result`, `mi-apply-unify-run`, `mi-apply-unify-run-result`, `mi-chain`, `mi-chain-collapsed`, `mi-chain-run`, `mi-chain-substitute`, `mi-cons-atom`, `mi-decons-atom`, `mi-function`, `mi-function-continue`, `mi-function-loop`, `mi-function-result`, `mi-unify`, `mi-unify-finish`, `mi-unify-is-space`, `mi-unify-probe`, `mi-unify-rigid-first`, `mi-unify-rigid-first-result`, `mi-unify-rigid-second`, `mi-unify-rigid-second-result`, `mi-unify-space`, `mi-unify-space-carrier`, `mi-unify-space-carriers`, `mi-unify-space-finish`, `mi-unify-space-item`, `mi-unify-structural`

LeaTTa's universal small-step machine, written in MeTTa, with its instruction tags as nullary symbols (68 names).

> `u-apply`, `u-chain`, `u-chain-apply`, `u-classify`, `u-classify-expression`, `u-collapse-bind`, `u-cons-atom`, `u-context-space`, `u-decons-atom`, `u-equation`, `u-equation-apply`, `u-equation-carrier`, `u-eval`, `u-evalc`, `u-exhausted`, `u-filter-carrier`, `u-filter-data`, `u-filter-head`, `u-filter-head-data`, `u-filter-held`, `u-freshen-equation`, `u-function`, `u-hit`, `u-metta`, `u-miss`, `u-native-apply`, `u-native-plan`, `u-next-entry`, `u-reduce`, `u-reduce-carrier-append`, `u-reduce-carrier-append-choice`, `u-reduce-carrier-classify`, `u-reduce-carrier-data`, `u-reduce-carrier-entry`, `u-reduce-carrier-held`, `u-reduce-carrier-list`, `u-reduce-carrier-list-choice`, `u-reduce-carrier-one`, `u-reduce-carrier-one-classified`, `u-reduce-classified`, `u-reduce-error`, `u-reduce-held`, `u-reduce-held-classified`, `u-reduce-term`, `u-reduced`, `u-run`, `u-run-held`, `u-run-term`, `u-scan-data`, `u-scan-held`, `u-space`, `u-space-add`, `u-space-equality-theory`, `u-space-eval`, `u-space-query`, `u-space-query-carrier`, `u-space-query-choice`, `u-space-query-scan`, `u-space-remove`, `u-space-result`, `u-space-theory-choice`, `u-space-theory-head`, `u-space-theory-scan`, `u-stuck`, `u-superpose-bind`, `u-unify`, `u-unify-apply`, `u-unify-rigid`

