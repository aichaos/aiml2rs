#!/usr/bin/perl

# rs2aiml - RiveScript to AIML converter.

use 5.14.0;
use strict;
use warnings;
use RiveScript;

if (!-d "./rs-in") {
	die "The rs-in/ directory doesn't exist. Create it, and put your RS documents there.";
}
if (!-d "./aiml-out") {
	mkdir("./aiml-out") or die "Couldn't create output folder ./aiml-out: $@";
}

our @warnings = ();
sub warning {
	my $str = shift;
	push (@warnings, $str);
}

# Start with begin.rs, if available. Convention says to put your definitions there.
if (-f "./rs-in/begin.rs") {
	say "Process: begin.rs";
	process("begin.rs");
}
opendir(my $dh, "./rs-in");
foreach my $file (sort(grep(/\.rs$/i, readdir($dh)))) {
	next if $file eq "begin.rs";
	say "Process: $file";
	process($file);
}
closedir($dh);

if (@warnings) {
	print "The following warnings were found. Some of the resulting AIML code\n";
	print "will need to be fixed by hand.\n\n";
	print scalar(@warnings) . " warning(s) found:\n" . join("\n", @warnings), "\n";
}

# Keep track of global arrays for triggers that need them.
my $arrays = {};
sub process {
	my $file = shift;

	# Load the RS document.
	my $rs = RiveScript->new();
	$rs->loadFile("./rs-in/$file");

	# Deparse it.
	my $deparse = $rs->deparse();

	# Are there arrays to keep track of?
	foreach my $name (keys %{$deparse->{begin}->{array}}) {
		$arrays->{$name} = $deparse->{begin}->{array}->{$name};
	}

	# Categories for AIML.
	my @categories;

	# Process the triggers.
	foreach my $topic (keys %{$deparse->{topic}}) {
		my $source = $deparse->{topic}->{$topic};
		push @categories, { topic => $topic };

		# Loop over the triggers.
		TRIGGER: foreach my $trigger (keys %{$source}) {
			my $info = $source->{$trigger}; # Reference to trigger details

			# Look up all permutations of this trigger.
			my @perms = permutations($trigger, $file, $deparse);
			if (@perms) {
				# Add a category for each permutation.
				my $original;
				foreach my $pattern (@perms) {
					my $category = {
						pattern => uc($pattern),
						template => '',
					};

					# A %previous?
					if (exists $info->{previous}) {
						$category->{that} = uc($info->{previous});
					}

					# Is the original permutation, or an alias?
					if (!defined $original) {
						$original = $pattern;
					}
					else {
						# It's an alias!
						$category->{template} = "\t\t<srai>" . uc($original) . "</srai>";
						push @categories, $category;
						next;
					}

					# Things to add to the <template>...
					my @template;

					# Are there conditions?
					if (exists $info->{condition}) {
						push @template, "<condition>";
						foreach my $condition (@{$info->{condition}}) {
							my ($left, $eq, $right, $result) = ($condition =~ /^(.+?)\s+(==|eq|!=|ne|<>|<|<=|>|>=)\s+(.+?)\s*=>\s*(.+?)$/);

							# We can only do == in AIML.
							if ($eq !~ /^(==|eq)$/) {
								push @warnings, "Conditions can only check == in AIML: $condition ($file)";
								next TRIGGER;
							}

							# Only makes sense to compare to user variables.
							if ($left =~ /^<get (.+?)>$/i) {
								my $var = $1;
								if ($right =~ /[^A-Za-z0-9 ]/) {
									push @warnings, "Condition is too complex for AIML: $condition ($file)";
									next TRIGGER;
								}

								push @template, "\t<li name=\"$var\" value=\"$right\">$result</li>";
							}
							else {
								push @warnings, "Condition is too complex for AIML: $condition ($file)";
							}
						}
						push @template, "\t<li>";
					}

					# Any redirects?
					if (exists $info->{redirect}) {
						push @template, "<srai>" . uc($info->{redirect}) . "</srai>";
					}

					# Replies.
					if (ref $info->{reply}) {
						my $random = scalar @{$info->{reply}} > 1;
						push @template, "<random>" if $random;
						foreach my $reply (@{$info->{reply}}) {
							my $indent = exists $info->{condition} ? "\t\t" : "";
							if ($random) {
								push @template, "$indent<li>$reply</li>";
							}
							else {
								push @template, "$indent$reply";
							}
						}
						push @template, "</random>" if $random;

						# End conditionals?
						if (exists $info->{condition}) {
							push @template, "\t</li>", "</condition>";
						}
					}

					$category->{template} = join("\n", map { "\t\t$_" } @template);
					push @categories, $category;
				}
			}
		}

		push @categories, { endtopic => $topic };
	}

	my @aiml = ('<aiml version="1.0">',
		'<!-- Converted using rs2aiml on: ' . (scalar(localtime())) . ' -->',
		'');

	my $intopic = 0;
	foreach my $category (@categories) {
		if ($category->{topic} && $category->{topic} ne "random") {
			push @aiml, "<topic name=\"$category->{topic}\">";
			$intopic = 1;
		}
		elsif ($category->{endtopic}) {
			push @aiml, "</topic>";
			$intopic = 0;
		}
		else {
			my $indent = $intopic ? "\t" : "";

			# Convert RS tags to AIML.
			$category->{template} = convert_tags($category->{template});

			# Look for illegal XML tags.
			if ($category->{template} =~ /<set .+?="[^"]*[<>][^"]*"/i) {
				push @warnings, "Illegal nested tags: $category->{template}";
				next;
			}

			push @aiml, "$indent<category>",
				"$indent\t<pattern>$category->{pattern}</pattern>";
			if ($category->{that}) {
				push @aiml, "$indent\t<that>$category->{that}</that>";
			}
			push @aiml, "$indent\t<template>",
				$category->{template},
				"$indent\t</template>";

			push @aiml, "$indent</category>";
		}
		push @aiml, "";
	}

	push @aiml, "", "</aiml>";

	# Write.
	my $name = $file;
	$name =~ s/\.rs$//ig;
	$name .= ".aiml";
	open (my $fh, ">", "./aiml-out/$name");
	print {$fh} join("\n",@aiml);
	close ($fh);

	print join("\n",@aiml);
}

sub convert_tags {
	my $template = shift;

	print $template;

	# Escape some common shortcut tags first.
	$template =~ s{<(star|star\d+|botstar|botstar\d+|formal)>}{__$1__}ig;

	# Variables.
	$template =~ s{<bot .+?=.+?>}{}ig; # AIML doesn't support setting botvars
	$template =~ s{<bot (.+?)>}{<bot name="$1" />}ig;
	$template =~ s{<set (.+?)=(.+?)>}{<think><set name="$1">$2</set></think>}ig;
	$template =~ s{<get (.+?)>}{<get name="$1" />}ig;
	$template =~ s{<(add|sub|mult|div|env) .+?>}{}ig; # AIML doesn't have these tags
	$template =~ s/\{topic=(.+?)\}/<set name="topic">$1<\/set>/ig;

	# Unescape.
	$template =~ s{__(star|star\d+|botstar|botstar\d+|formal)__}{<$1>}ig;

	# Star tags.
	$template =~ s{<star>}{<star1>}ig;
	$template =~ s{<botstar>}{<botstar1>}ig;
	$template =~ s{<star(\d+)>}{<star index="$1" />}ig;
	$template =~ s{<botstar(\d+)>}{<thatstar index="$1" />}ig;

	# Input/response.
	$template =~ s/<(input|reply)>/<${1}1>/ig;
	$template =~ s{<input(\d+)>}{<request index="$1" />}ig;
	$template =~ s{<reply(\d+)>}{<response index="$1" />}ig;

	# Shortcut tags.
	$template =~ s{<@>}{<sr />}g;
	$template =~ s{<person>}{<person />}ig;
	$template =~ s{<formal>}{<formal><star index="1" /></formal>}ig;
	$template =~ s{<sentence>}{<sentence><star index="1" /></sentence>}ig;
	$template =~ s{<uppercase>}{<uppercase><star index="1" /></uppercase>}ig;
	$template =~ s{<lowercase>}{<lowercase><star index="1" /></lowercase>}ig;

	# String format tags.
	$template =~ s/{(\/|)(person|formal|uppercase|lowercase)}/<$1$2>/ig;

	# Small tags.
	$template =~ s{<id>}{<id />}ig;
	$template =~ s{\\n}{\n}g;
	$template =~ s{\\s}{ }g;

	# Inline redirects.
	while ($template =~ /\{\@(.+?)\}/) {
		my $redir = $1;
		$redir =~ s/^\s+//g;
		$redir =~ s/\s+$//g;
		$redir = uc($redir);
		$template =~ s/\{\@.+?\}/<srai>$redir<\/srai>/i;
	}

	# Random.
	while ($template =~ /\{random\}(.+?)\{\/random\}/i) {
		my $rand = $1;
		my @output = ("<random>");
		if ($rand =~ /\|/) {
			foreach (split(/\|/, $rand)) {
				push @output, "\t<li>$_</li>";
			}
		}
		else {
			foreach (split(/\s+/, $rand)) {
				push @output, "\t<li>$_</li>";
			}
		}
		push @output, "</random>";
		my $text = join("\n",@output);
		$template =~ s/\{random\}.+?\{\/random\}/$text/i;
	}

	# Object calls.
	$template =~ s{<call>.+?</call>}{}ig; # Remove them

	return $template;
}

sub permutations {
	my ($trigger, $file, $deparse) = @_;

	$trigger =~ s/{weight=\d+}//g; # Remove weight tags

	# Simple triggers with no permutations?
	if ($trigger !~ /\(|\[|\@/) {
		return ($trigger);
	}

	# Collect variable groups. Groups are: alternations, optionals,
	# and arrays. Replace each group with a numbered placeholder.
	my @groups;
	while ($trigger =~ /\@(.+?)\b/) { # arrays
		my $name = $1;
		if (exists $arrays->{$name}) {
			push @groups, $arrays->{$name};
			my $id = "{PH:" . scalar(@groups) . "}"; # Placeholder
			$trigger =~ s/\@.+?\b/$id/;
			$trigger =~ s/\(\Q$id\E\)/$id/; # parens around the (@array) don't matter here
		}
		else {
			push @warnings, "Reference to array '$name' that wasn't found in $trigger ($file)";
			return undef;
		}
	}
	while ($trigger =~ /\((.+?)\)/) { # alternations
		my $alt = $1;
		if ($alt =~ /\(|\[/) { # embedded??
			push @warnings, "Embedded alt/opt groups in $trigger ($file)";
			return undef;
		}

		push @groups, [ split(/\|/, $alt) ];
		my $id = "{PH:" . scalar(@groups) . "}"; # Placeholder
		$trigger =~ s/\(.+?\)/$id/;
	}
	while ($trigger =~ /\[(.+?)\]/) { # optionals
		my $opt = $1;
		if ($opt =~ /\(|\[/) { # embedded??
			push @warnings, "Embedded alt/opt groups in $trigger ($file)";
			return undef;
		}

		push @groups, [
			(map { " $_ " } split(/\|/, $opt)), # for each optional word
			" ",                                # for none of them at all
		];

		my $id = "{PH:" . scalar(@groups) . "}"; # Placeholder
		$trigger =~ s/\s*\[.+?\]\s*/$id/; # remove spaces around it too
	}

	#print "TRIG: $trigger\n";
	#foreach my $grp (@groups) {
	#	print "G: @{$grp}\n";
	#}

	my @combos = permute(@groups);
	my @strings;
	foreach my $c (@combos) {
		my $string = $trigger;
		for (my $i = 0; $i < scalar(@groups); $i++) {
			my $index = $i+1;
			my $id    = "{PH:$index}";
			$string   =~ s/\Q$id\E/$c->[$i]/;
		}

		$string =~ s/\s+/ /g;
		$string =~ s/^\s+//g;
		$string =~ s/\s+$//g;
		push @strings, $string;
	}

	return @strings;
}

sub permute {
	my $last = pop @_;
	unless (@_) {
		return map [$_], @{$last};
	}
	return map { my $left = $_; map [@{$left}, $_], @{$last} } permute(@_);
}
