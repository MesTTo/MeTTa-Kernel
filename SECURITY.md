# Security policy

PeTTa is alpha software. Versions are `0.y.z`, every release is labelled
alpha, breaking changes are expected at each one, and there is no maintenance
line beside the branch under development. A fix therefore lands on that branch
and is carried by the next tag rather than being backported to an older one.

## Reporting a vulnerability

Report privately, by email, to a.mesto@student.unsw.edu.au. It is a commit
identity in this repository's history, not an address that exists only on this
page, so `git log` checks it.

Do not open a public issue, discussion or pull request for a vulnerability.
The issue templates are for ordinary defects, and everything filed through
them is public from the moment it is filed.

A report is quickest to act on when it carries:

- the MeTTa program, Python snippet or command that triggers it, small enough
  to run as it stands;
- what the attacker gets, and what access they need before they get it;
- the commit or tag you saw it on, with the SWI-Prolog and Python versions;
- the fix you would make, if one is already clear to you.

## Coordinated disclosure, 90 days

The details stay private for up to 90 days from the day the report arrives,
while the fix is written, tested and released. That is a ceiling and not a
target. A fix that ships sooner moves publication up with it, and a report
that needs longer than 90 days gets a new date agreed with you rather than
assumed.

When the fix is released, the report becomes public along with it.

## No bounty

There is no bug bounty and no payment of any kind for a report. What a
reporter gets is the fix and the credit: the changelog entry names you by
whatever name you ask for, or names nobody if you would rather stay
anonymous.
