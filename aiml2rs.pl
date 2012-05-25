#!/usr/bin/perl

use 5.14.0;
use strict;
use warnings;
use XML::TokeParser;
use File::Copy;

if (!-d "./aiml") {
	die "The aiml/ directory doesn't exist. Create it, and put your AIML documents there.";
}
if (!-d "./rs") {
	mkdir("./rs") or die "Couldn't create output folder ./rs: $@";
}

# Alice topics? (not real topics)
my $AliceTopics = 1;

our @warnings = ();
sub warning {
	my $str = shift;
	push (@warnings, $str);
}

opendir(my $dh, "./aiml");
foreach my $file (sort(grep(/\.aiml$/i, readdir($dh)))) {
	say "Process: $file";
	process($file);
}
closedir($dh);

# Copy begin.rs.
copy("./begin.rs", "./rs/rs-begin.rs");

if (@warnings) {
	print "The following warnings were found. Some of the resulting RS code\n";
	print "will need to be fixed by hand.\n\n";
	print scalar(@warnings) . " warning(s) found:\n" . join("\n", @warnings), "\n";

	# Categorize them.
	my %cat = (random => 0, unhandled => 0, condition => 0);
	foreach my $w (@warnings) {
		if ($w =~ /^Embedded random/) {
			$cat{random}++;
		}
		elsif ($w =~ /^Unhandled/) {
			$cat{unhandled}++;
		}
		elsif ($w =~ /^Condition/) {
			$cat{condition}++;
		}
	}

	print "\n"
		. "Categorized, the following types of warnings were found:\n"
		. "Embedded <random> tags: $cat{random}\n"
		. "Unhandled AIML tags:    $cat{unhandled}\n"
		. "Conditional tags:       $cat{condition}\n";
}

sub process {
	my $file = shift;

	open (my $fh, "<:utf8", "aiml/$file");
	my $p = XML::TokeParser->new($fh);

	# Final container of parsed AIML categories.
	my $parsed = {};

	# Temp state variables.
	my $topic    = "random"; # Default topic
	my $buffer   = ''; # Current text buffer for current {pattern,that,template,...}
	my $inTag    = ''; # In a significant container tag (pattern,that,template,...)
	my $category = {}; # Category buffer (added to $parsed on </category>)
	my $thinking = 0;  # Are we inside a <think> tag?
	my $setVar   = ""; # The variable named in a <set name="x"> tag.
	my $setVal   = ""; # The text for setting a variable.
	my $inRandom = 0;  # Inside a <random> tag.
	my @random   = (); # Buffer for <li>'s inside a <random>
	my $inCond   = 0;  # Inside a <condition> tag.
	my $condName = ""; # Condition name (<condition name="x">)
	my @conds    = (); # The conditions
	my $tainted  = 0;  # Tainted replies w/ embedded <random>'s or conditions we can't handle

	# Parse.
	while (my $t = $p->get_token) {
		my $event = $t->[0];

		# Comments
		if ($event eq "C") {
			next;
		}

		# A text node?
		if ($event eq "T") {
			my $text = $t->text;
			$text =~ s/^[\t\n]+//g;
			$text =~ s/[\t\n]+$//g;
			$text =~ s/\s+/ /g;

			# Inside a set tag?
			if ($setVar) {
				$setVal .= $text;
			}
			elsif ($inRandom) {
				push @random, "" unless scalar @random;
				$random[-1] .= $text;
			}
			elsif ($inCond) {
				if (scalar(@conds) > 0) {
					$conds[-1] .= $text;
				}
			}
			else {
				$buffer .= $text;
			}
			next;
		}

		# Many tags want to add some buffer text. This will be handled
		# in the "default" case.
		my $newText = "";

		# Handle tags.
		given (lc($t->tag)) {
			when ("aiml") {
				# AIML tag.
			}
			when("topic") {
				next if $AliceTopics; # Ignore these for AliceTopics
				if ($event eq "S") { # Start tag
					$topic = $t->attr->{name};
					say "Set topic to: $topic";
				}
			}
			when("category") {
				if ($event eq "S") {
					# Start a new category.
					$category = {};
					$tainted  = 0;
				}
				elsif ($event eq "E") {
					# This is </category>.
					next if $tainted;
					if (!exists $parsed->{$topic}) {
						$parsed->{$topic} = [];
					}

					# Conditions?
					if (@conds) {
						$category->{condition} = [ @conds ];
						@conds = ();
					}
					push @{$parsed->{$topic}}, $category;
				}
			}
			when(/(pattern|that|template)/) {
				if ($event eq "S") {
					# Start tag.
					$inTag = $t->tag;
					$buffer = "";
				}
				elsif ($event eq "E") {
					# End tag.
					if ($t->tag eq "pattern" && $buffer =~ /_/) {
						$buffer =~ s/_/*/g;
					}
					$category->{$t->tag} = $buffer;
				}
			}
			when("think") {
				# The <think> tag, controls whether <set>s need to be echo'd back or not.
				$thinking = $event eq "S" ? 1 : 0;
			}
			when(/^(star|input|request|response)$/) {
				# The <star>, <input> and <that/reply> tags.
				if ($event eq "S") {
					my $rs = $t->tag;
					$rs = "reply" if $rs eq "response";
					$rs = "input" if $rs eq "request";
					my $index = $t->attr->{index} || 1;
					my $text = "<$rs$index>";
					$text = "<$rs>" if $index == 1;

					$newText = $text;
					continue;
				}
			}
			when("id") {
				if ($event eq "S") {
					$newText .= "<id>";
					continue;
				}
			}
			when(/^(bot|get|get_.+?)$/) {
				# <bot name="x"/>, <get name="x"/>
				if ($event eq "S") {
					my $tag = $t->tag;

					my $var = $t->attr->{name} || "";

					# Old-style <get> tag?
					if ($tag =~ /^get_(.+?)$/) {
						$tag = "get";
						$var = $1;
					}

					if ($var) {
						$newText = "<$tag $var>";
						continue;
					}
				}
			}
			when("set") {
				# A set tag.
				if ($event eq "S") {
					# Get the name of it.
					$setVar = $t->attr->{name};
					$setVal = "";
				}
				elsif ($event eq "E") {
					# The tag is complete.
					next unless $setVar;

					# Alice topics? (avoid clashing with RS {topic})
					if ($setVar eq "topic" && $AliceTopics) {
						$setVar = "alicetopic";
					}

					# Special hack to formalize names.
					if ($setVar eq "name") {
						$setVal = "{formal}" . $setVal . "{/formal}";
					}

					# Delete if blank
					if ($setVal eq "" || $setVal eq "{formal}{/formal}") {
						$setVal = "<undef>";
					}

					$newText = "<set $setVar=$setVal>";

					# Echo it back immediately unless <think>.
					unless ($thinking) {
						$newText .= "<get $setVar>";
					}

					$setVar = "";
					$setVal = "";
					continue;
				}
			}
			when("random") {
				# A <random> tag.
				if ($event eq "S") {
					# Begin the random buffer.
					if ($inRandom) {
						# Warning! Embedded randoms!
						warning("Embedded randoms at $file in pattern $category->{pattern}");
						$tainted = 1;
					}
					$inRandom = 1;
					@random = ();
				}
				elsif ($event eq "E") {
					$inRandom = 0;
					my $text = join("|", map { trim($_) } grep { !/^\s+$/ } @random);
					@random = ();
					$newText = "{random}" . $text . "{/random}";
					continue;
				}
			}
			when("condition") {
				# Attempt to handle condition tags.
				if ($event eq "S") {
					# We only bother with super simple conditions that follow this pattern:
					# <template>
					#  <condition name="x">
					#   <li value="y">...</li>
					#  </condition>
					# </template>
					$condName = $t->attr->{name} || "";
					$inCond   = 1;
					@conds    = ();
				}
				elsif ($event eq "E") {
					$inCond = 0;
					$condName = "";
				}
			}
			when("li") {
				# <li> can be part of <random> or <condition>
				if ($inRandom) {
					if ($event eq "S") {
						# New random buffer.
						push @random, "";
					}
				}
				elsif ($inCond) {
					if ($event eq "S") {
						# In a condition.
						my $name = $condName || (ref $t->attr ? $t->attr->{name} : "");
						if (!$name) {
							# Abort!
							warning("Condition too complicated to handle at $file in pattern $category->{pattern}");
						}
						my $value = "";
						if (ref($t->attr)) {
							$value = $t->attr->{value} || "";
						}
						if ($value) {
							# Handle special values.
							$value = "undefined" if $value =~ /^unknown$/i; # unknown -> undefined
							$value = "undefined" if $value =~ /^om$/i;      # TODO: Alice's brain has this
							if ($value eq "*") {
								# * = not undefined
								push @conds, "<get $name> != undefined => ";
							}
							else {
								push @conds, "<get $name> == $value => ";
							}
						}
						else {
							# Default condition.
							$inCond = 0;
						}
					}
				}
				else {
					continue;
				}
			}
			when("srai") {
				# <srai> tag.
				my $text = $event eq "S" ? "{@" : "}";
				if ($event eq "S" || $event eq "E") {
					$newText = $text;
					continue;
				}
			}
			when(/^(sr|person)$/) {
				# <sr/>, <person/>, etc
				my $text = "";
				if ($t->tag eq "sr") {
					$text = '<@>';
				}
				else {
					$text = "<" . $t->tag . ">";
				}

				if ($event eq "S") {
					$newText = $text;
					continue;
				}
			}
			when(/^(uppercase|lowercase|formal|sentence)$/) {
				my $text = $event eq "S" ? "{" . $t->tag . "}" : "{/" . $t->tag . "}";
				if ($event eq "S" || $event eq "E") {
					$newText = $text;
					continue;
				}
			}
			when(/^(date|size)$/) { # Alice special tags
				if ($event eq "S") {
					my $tag = $1;
					my $arg = "";
					if ($tag eq "date") {
						my $format = $t->attr->{format};
						if ($format) {
							$arg = " $format";
						}
					}
					$newText = "<call>$tag$arg</call>";
				}
			}
			default {
				# New buffer text given above?
				my $handled = 0;
				if (!length $newText) {
					# Nope, then add this tag.
					$newText = $t->raw;
				}
				else {
					$handled = 1;
				}

				# All the other tags.
				if ($setVar) {
					$setVal .= $newText;
				}
				elsif ($inRandom) {
					push @random, "" unless scalar @random;
					$random[-1] .= $newText;
				}
				elsif ($inCond) {
					if (scalar @conds > 0) {
						$conds[-1] .= $newText;
					}
				}
				else {
					$buffer .= $newText;
				}

				# Log about unhandled tags (skip common HTML ones).
				next if $t->tag =~ /^(a|b|i|u|br|ul|p|li|em|img)$/i; # HTML tags
				next if $t->tag =~ /^(eval|learn)$/i; # AIML tags
				next if $t->tag =~ /^(oob|dial|dialcontact|map|search|sms|recipient|message)$/i; # AIML CallMom tags
				next if $handled;
				warning("Unhandled AIML tag " . $t->raw);
			}
		}
	}

	toRiveScript($file, $parsed);
}

sub toRiveScript {
	my ($file,$parsed) = @_;

	my $rs = $file;
	$rs =~ s/\.aiml$//ig;
	$rs .= ".rs";

	open (my $fh, ">:utf8", "./rs/$rs");
	print {$fh} "// Converted using aiml2rs on: " . scalar(localtime()) . "\n"
		. "! version = 2.0\n\n";

	foreach my $topic (sort keys %{$parsed}) {
		if ($topic ne "random") {
			print {$fh} "> topic $topic\n\n";
		}

		foreach my $category (@{$parsed->{$topic}}) {
			my $trig = lc($category->{pattern});

			# Skip triggers with syntax errors.
			if ($trig =~ /[^A-Za-z0-9<>\{\}= \*_\#\(\)\[\]]/) {
				warn "Trigger '$trig' has syntax errors. Skipping.";
				next;
			}

			print {$fh} "+ $trig\n";

			if ($category->{that}) {
				my $that = lc($category->{that});
				$that =~ s/[^A-Za-z0-9<>\{\}= \*_\#\(\)\[\]]//g;
				print {$fh} "% $that\n";
			}

			# Conditions
			if (exists $category->{condition}) {
				foreach my $c (@{$category->{condition}}) {
					$c =~ s/\n/\\n/g;
					$c =~ s/<br.+?>/\\n/g;
					$c =~ s/[\x0D\x0A]+//g;
					print {$fh} "* $c\n";
				}
			}

			my $temp = $category->{template};
			$temp =~ s/\n/\\n/g;
			$temp =~ s/<br.+?>/\\n/g;
			$temp =~ s/[\x0D\x0A]+//g;

			# Lowercase redirects.
			$temp =~ s/\{\@([^\}\@]+?)\}/\L{\@$1}\E/g;

			# Handle full-template random's.
			if ($temp =~ /^\{random\}(.+?)\{\/random\}$/i) {
				my @rand = split(/\|/, $1);
				foreach my $r (@rand) {
					next unless length $r > 0;
					print {$fh} "- $r\n";
				}
				print {$fh} "\n";
			}

			# Handle full-template redirects.
			elsif ($temp =~ /^\{\@([^\}\@]+?)\}$/i) {
				my $redir = $1;
				$redir =~ s/[^A-Za-z0-9<>\{\}= \*_\#\(\)\[\]]//g;
				print {$fh} "\@ " . lc($redir) . "\n\n";
			}

			# Atomic reply
			else {
				print {$fh} "- $temp\n\n";
			}
		}

		if ($topic ne "random") {
			print {$fh} "< topic\n\n";
		}
	}

	close ($fh);
}

sub trim {
	my $s = shift;
	$s =~ s/^\s+//g;
	$s =~ s/\s+$//g;
	return $s;
}
