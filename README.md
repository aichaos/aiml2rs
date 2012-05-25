aiml2rs
=======

Tools to convert AIML code into RiveScript code -- and back!

Scripts
=======

The `aiml2rs.pl` script does all the magic of converting Alice AIML code into
RiveScript code.

The `rs2aiml.pl` script does the opposite: converting RiveScript code back
into AIML code.

How to Use
==========

Place all your `*.aiml` files in the `aiml/` directory, and then run the
script. It will attempt to convert all the AIML code into RiveScript, and
will output the results into the `rs/` directory.

For rs2aiml, place your `*.rs` files in the `rs-in/` dirctory, and then run
`rs2aiml.pl`. It will attempt to convert the RS code into AIML, and output
the results into `aiml-out/`.

Caveats
=======

There are some things that this converter won't be able to translate
automatically. These are:

1) Embedded `<random>` tags are not supported. Currently none of the RiveScript
interpreters are able to handle embedded random tags either.

2) Complicated conditionals. There are only a couple of these in Alice's AIML
set. Simple conditions should work though (ones where there is only one
`<condition>` tag, and it takes up the entirety of the template). Embedded
conditions? Forget about it.

For the cases that `aiml2rs` doesn't handle automatically, it will print out the
AIML file name and `<pattern>` where the anomoly occurred, so that you can go
and enter it in manually. `aiml2rs` won't attempt to generate RiveScript code for
triggers that have issues like this.

When converting from RiveScript back to AIML, the following limitations exist:

1) Nested parenthesis groups in triggers will be skipped. These are triggers
where you include optionals INSIDE an alternation group, or any similar combination.
These kinds of triggers can't be permutated cleanly, so are skipped.

2) Nested `<set>` tags will be skipped (ie. `<set fav<star1>=<star2>>`, because
AIML doesn't support this.

3) Any conditionals besides a simple `<get variable> == value` will result in
the entire reply being skipped, because AIML doesn't support any kind of
condition except `==` on user variables.

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
