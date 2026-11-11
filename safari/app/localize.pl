#!/usr/bin/perl
# Стопка: добавляет русскую локализацию в сгенерированный Xcode-проект.
#
#   plutil -convert json -o - project.pbxproj | perl localize.pl Stopka > new.json
#   perl localize.pl Stopka < project.xcproj > new.xcproj        # Xcode 27.2+
#
# Конвертер даёт проекту только en/Base. Чтобы App Store показывал
# «English, Russian», а приложение на русской системе отвечало по-русски,
# в цель приложения нужен ru.lproj: окно (Main.html), меню (Main.strings)
# и имя (InfoPlist.strings). Сами файлы кладёт build.sh, здесь — только
# записи о них в проекте. Работаем со структурой проекта, а не с текстом.
#
# Форматов два. Старый project.pbxproj (plist, сюда приходит JSON из plutil)
# и новый project.xcproj — его конвертер Xcode 27.2 пишет вместо pbxproj:
# JSON с висячими запятыми. Его читаем в режиме relaxed, обратно пишем
# обычным JSON — Xcode такой принимает (проверено `xcodebuild -list`).
use strict;
use warnings;
use JSON::PP;
use Digest::MD5 qw(md5_hex);

my $app = shift or die "нужно имя цели приложения\n";
binmode STDIN, ':raw';
my $data = JSON::PP->new->relaxed->decode(do { local $/; <STDIN> });

if (exists $data->{objects}) { pbxproj() }
elsif (exists $data->{files} && exists $data->{targets}) { xcproj() }
else { die "незнакомый формат проекта\n" }

print JSON::PP->new->pretty->canonical->encode($data);

# --- project.xcproj (Xcode 27.2+) ---
# Файлы — дерево групп; принадлежность цели — "target-membership": ["Stopka/resources"].
# Язык файла внутри вариантной группы Xcode берёт из папки *.lproj в пути.
sub xcproj {
  my $res = "$app/resources";
  my $sup = ($data->{localizations} //= {})->{supported} //= [];
  push @$sup, 'ru' unless grep { $_ eq 'ru' } @$sup;

  # Вариантная группа цели приложения и её родительская группа.
  my $find; $find = sub { my ($nodes, $parent, $name) = @_;
    for my $n (@$nodes) {
      return ($n, $parent) if ($n->{kind} // '') eq 'variant-group' && ($n->{name} // '') eq $name
                             && grep { $_ eq $res } @{ $n->{'target-membership'} // [] };
      if (my @hit = $find->($n->{children} // [], $n, $name)) { return @hit }
    }
    return };
  my $variant = sub { my $name = shift;
    my @hit = $find->($data->{files}, undef, $name);
    die "нет вариантной группы $name в цели $app\n" unless @hit; return @hit };

  my ($html) = $variant->('Main.html');
  push @{ $html->{children} }, { path => 'ru.lproj/Main.html' };
  my ($storyboard, $parent) = $variant->('Main.storyboard');
  push @{ $storyboard->{children} }, { path => 'ru.lproj/Main.strings' };

  # InfoPlist.strings: новой вариантной группы нет — заводим рядом со storyboard.
  die "не нашёл группу со storyboard\n" unless $parent;
  push @{ $parent->{children} }, { kind => 'variant-group', name => 'InfoPlist.strings',
    'target-membership' => [$res], children => [ { path => 'ru.lproj/InfoPlist.strings' } ] };
}

# --- project.pbxproj (до Xcode 27.2) ---
sub pbxproj {
  my $o = $data->{objects};
  my $root = $o->{ $data->{rootObject} };

  # Новые ID: 24 hex-символа, стабильные между запусками и без коллизий.
  my $new_id = sub { my $id = uc substr(md5_hex("stopka-ru-" . shift), 0, 24);
                     die "ID $id уже занят\n" if exists $o->{$id}; return $id };

  my ($target) = grep { ($_->{isa} // '') eq 'PBXNativeTarget' && $_->{name} eq $app } values %$o;
  die "нет цели $app\n" unless $target;
  my ($resources) = grep { $o->{$_}{isa} eq 'PBXResourcesBuildPhase' } @{ $target->{buildPhases} };
  die "у цели $app нет фазы Resources\n" unless $resources;

  # Вариантные группы цели приложения: те, что собираются в её Resources.
  my %in_target = map { $o->{$_}{fileRef} // '' => 1 } @{ $o->{$resources}{files} };
  my $variant = sub { my $name = shift;
    my ($id) = grep { ($o->{$_}{isa} // '') eq 'PBXVariantGroup' && $o->{$_}{name} eq $name && $in_target{$_} } keys %$o;
    die "нет вариантной группы $name в цели $app\n" unless $id; return $id };

  my $add_ru = sub { my ($group, $path, $type) = @_;
    my $id = $new_id->($path);
    $o->{$id} = { isa => 'PBXFileReference', lastKnownFileType => $type, name => 'ru',
                  path => $path, sourceTree => '<group>' };
    push @{ $o->{$group}{children} }, $id; return $id };

  push @{ $root->{knownRegions} }, 'ru' unless grep { $_ eq 'ru' } @{ $root->{knownRegions} };

  $add_ru->($variant->('Main.html'), 'ru.lproj/Main.html', 'text.html');
  my $storyboard = $variant->('Main.storyboard');
  $add_ru->($storyboard, 'ru.lproj/Main.strings', 'text.plist.strings');

  # InfoPlist.strings: новой вариантной группы нет — заводим рядом со
  # storyboard, в той же папке, и добавляем в Resources цели.
  my ($parent) = grep { ($o->{$_}{isa} // '') eq 'PBXGroup' && grep { $_ eq $storyboard } @{ $o->{$_}{children} } } keys %$o;
  die "не нашёл группу со storyboard\n" unless $parent;
  my $vg = $new_id->('InfoPlist.strings group');
  $o->{$vg} = { isa => 'PBXVariantGroup', name => 'InfoPlist.strings', children => [], sourceTree => '<group>' };
  push @{ $o->{$parent}{children} }, $vg;
  $add_ru->($vg, 'ru.lproj/InfoPlist.strings', 'text.plist.strings');
  my $bf = $new_id->('InfoPlist.strings in Resources');
  $o->{$bf} = { isa => 'PBXBuildFile', fileRef => $vg };
  push @{ $o->{$resources}{files} }, $bf;
}
