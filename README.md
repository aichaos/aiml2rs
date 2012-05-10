aiml2rs
=======

Tools to convert AIML code into RiveScript code.

Scripts
=======

The `aiml2rs.pl` script does all the magic of converting Alice AIML code into
RiveScript code.

How to Use
==========

Place all your `*.aiml` files in the `alice/` directory, and then run the
script. It will attempt to convert all the AIML code into RiveScript, and
will output the results into the `rs/` directory.

Caveats
=======

There are some things that this converter won't be able to translate
automatically. These are:

1) Embedded `<random>` tags are not supported. Currently none of the RiveScript
interpreters are able to handle embedded random tags either.

2) Conditionals. The Alice AIML set tends to embed conditions in the middle of
a template and RiveScript doesn't work this way.

For the cases that `aiml2rs` doesn't handle automatically, it will print out the
AIML file name and `<pattern>` where the anomoly occurred, so that you can go
and enter it in manually. `aiml2rs` won't attempt to generate RiveScript code for
triggers that have issues like this.

Alice AIML Quirks
=================

There are a number of patterns in the Alice AIML set that are invalid (they
contain foreign symbols for example). These patterns will be skipped when
converting to RiveScript (a warning is given during the conversion process).

Troubleshooting
===============

If the script crashes with an error that originated from `XML::Parser`, it is
most likely because an invalid character appeared in the AIML input (for example
a Unicode symbol). The error message is hard to read, but it will point you to
the line number in the AIML document where the error occurred.

The Alice set included in this repo was downloaded on May 9, 2012 and the Unicode
symbols in it were removed. If you use your own AIML set and get these errors,
you'll have to fix them yourself.
