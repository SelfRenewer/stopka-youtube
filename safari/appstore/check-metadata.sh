#!/bin/bash
# Стопка: проверяет тексты metadata.md на лимиты App Store Connect.
# Считает символы, а не байты: кириллица в UTF-8 занимает по два байта.
set -euo pipefail
cd "$(dirname "$0")"
perl -CSD -Mutf8 -ne '
  sub flush { return unless defined $name; (my $t = $text) =~ s/^\s+|\s+$//g;
    my $n = length $t; my $ok = $n <= $limit && $n > 0 ? "ок" : "ПРЕВЫШЕН";
    printf "%-20s %4d / %-4d %s\n", $name, $n, $limit, $ok; $bad++ if $ok ne "ок";
    if ($name eq "Ключевые слова") { for (split /,/, $t) {
      if (length($_) <= 2 || /^\s|\s$/) { print "  плохое слово: «$_»\n"; $bad++ } } }
    undef $name }
  if (/^## (.+)/) { flush(); $pending = $1; next }
  if (defined $pending && /<!-- limit:(\d+) -->/) { $name = $pending; $limit = $1; $text = ""; undef $pending; next }
  $text .= $_ if defined $name;
  END { flush(); exit($bad ? 1 : 0) }
' metadata.md
