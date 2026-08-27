;A program has to keep what it knows somewhere, and in MeTTa that somewhere
;is a SPACE. &self is the one every file already has.
;
;An atom goes in with add-atom. Nothing is declared first: (parent tom bob)
;is not an instance of a type, it is a piece of structure, and the space
;takes structure.
!(add-atom &self (parent tom bob))
!(add-atom &self (parent tom liz))
!(add-atom &self (parent bob ann))
!(add-atom &self (parent bob pat))
!(add-atom &self (parent pat jim))

;The space now holds five atoms, and space-atom-count says how many. This is
;the whole of "loading data": there is no schema and no table.
!(test (space-atom-count &self) 5)

;Nothing here says what `parent` MEANS. It means whatever the next file asks
;of it, which is the point: the facts came first and the questions come
;after. Chapter 4 is where spaces get their own chapter.
