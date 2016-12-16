# aiml2rs

This is a program to translate AIML code into RiveScript (or vice versa).

# Usage

```
aiml2rs <-rs || -aiml> -in <input directory> -out <output directory>
```

To translate AIML into RiveScript:

```
aiml2rs -rs -in ./aiml -out ./rs
```

Or to translate RiveScript into AIML:

```
aiml2rs -aiml -in ./rs -out ./aiml
```

If you're testing this program in development, you can substitute the
`aiml2rs` commands above with `go run main.go`, and with the same command
line parameters.

# Options

```
-aiml
    Convert from RiveScript to AIML. This option is mutually exclusive
    with `-rs`.

-rs
    Convert from AIML to RiveScript. This option is mutually exclusive
    with `-aiml`.

-in PATH
    This should be a path to a directory containing your input files.
    If you used `-rs`, this path should contain AIML files (*.aiml).
    If you used `-aiml`, this should contain RiveScript files (*.rive).

-out PATH
    This should be the path to a directory that you want your output
    files to be written to. This path does not need to exist; it will
    be created if needed.

    The files in the output path will have the same names as the input
    files, but with the file extension swapped, and obviously, with the
    expected output format (RiveScript or AIML) inside.

-real-topics
    The A.L.I.C.E. AIML brain makes liberal use of `<set topic>` where
    it treats the topic as just another user variables. Topics have a
    more strict meaning to RiveScript, so, by default, a `<set topic>`
    in AIML becomes `<set alicetopic>` in RiveScript.

    If you want the RiveScript output to use 'real' topics (`> topic`
    labels), provide the `-real-topics` option. Note that an Alice
    bot converted this way will probably misbehave due to the difference
    in topic behaviors between AIML and RiveScript.

-v
    Prints the program version and exits.

-debug
    Enable debug mode. This will result in very noisy output; for
    example, in AIML-to-RS mode it will print every opening and
    closing XML tag that it finds while parsing AIML files.
```
