# Real third-party source fixtures

These files are **unmodified third-party code**, fetched from a public,
independently developed provider repository:

    https://github.com/Spyou/zangetsu-providers
    https://raw.githubusercontent.com/Spyou/zangetsu-providers/main/index.json
    .../providers/anikoto.js, hdhub4u.js, fourkhdhub.js, torbox.js, animecube.js

They are committed **verbatim**, with no edits of any kind.

## Why they are here

Every other compatibility fixture in this repository was written by us, to
match what SPECTA already understood. That made the compatibility layer look
far more capable than it was: the fixtures used SPECTA's own operation names
(`search`, `getSources`, ...), so the alias problem could not show up.

Real third-party providers do not. These five export **nothing at all** — they
are plain scripts declaring top-level functions — and they name those
operations `getInfo`, `search`, `getHome`, `getDetail`, `getEpisodes` and
`getVideoSources`.

Testing against them exposed three genuine defects:

1. the generated shim returned the empty `module.exports` object and never fell
   back to the script global, so the source installed and then failed on the
   first call;
2. operation detection required SPECTA's own names, so three of the four
   contract operations were reported missing;
3. the shim called the contract name rather than the author's real function.

## What is asserted against them

`source_compatibility_test.dart` and `third_party_execution_test.dart` use
these files to prove that a genuine, independently written provider is
recognised, adapted, and — on the real QuickJS engine — actually executes.

## Rules for anyone editing this folder

* **Do not edit the `.js` files.** Their value is that they are real. A
  "cleaned up" fixture would reintroduce the exact blind spot described above.
* **Do not add provider names to the alias table.** The table maps *spellings*
  to contract slots, never authors, hosts or sites. A new ecosystem is
  supported by the names its code happens to use, not by being recognised.
* These files are third-party code. They are test data only: nothing in
  `lib/` ships them, and no test contacts any host they mention.
