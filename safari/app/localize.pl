#!/usr/bin/perl
# Стопка: добавляет русскую локализацию в сгенерированный Xcode-проект.
#
#   plutil -convert json -o - project.pbxproj | perl localize.pl Stopka > new.json
#
# Конвертер даёт проекту только en/Base. Чтобы App Store показывал
# «English, Russian», а приложение на русской системе отвечало по-русски,
# в цель приложения нужен ru.lproj: окно (Main.html), меню (Main.strings)
# и имя (InfoPlist.strings). Сами файлы кладёт build.sh, здесь — только
# записи о них в проекте. Работаем со структурой plist, а не с текстом.
use strict;
use warnings;
use JSON::PP;
use Digest::MD5 qw(md5_hex);

my $app = shift or die "нужно имя цели приложения\n";
binmode STDIN, ':raw';
my $data = decode_json(do { local $/; <STDIN> });
my $o = $data->{objects};
my $root = $o->{ $data->{rootObject} };

# Новые ID: 24 hex-символа, стабильные между запусками и без коллизий.
sub new_id { my $id = uc substr(md5_hex("stopka-ru-" . shift), 0, 24);
             die "ID $id уже занят\n" if exists $o->{$id}; return $id }

my ($target) = grep { ($_->{isa} // '') eq 'PBXNativeTarget' && $_->{name} eq $app } values %$o;
die "нет цели $app\n" unless $target;
my ($resources) = grep { $o->{$_}{isa} eq 'PBXResourcesBuildPhase' } @{ $target->{buildPhases} };
die "у цели $app нет фазы Resources\n" unless $resources;

# Вариантные группы цели приложения: те, что собираются в её Resources.
my %in_target = map { $o->{$_}{fileRef} // '' => 1 } @{ $o->{$resources}{files} };
sub variant { my $name = shift;
  my ($id) = grep { ($o->{$_}{isa} // '') eq 'PBXVariantGroup' && $o->{$_}{name} eq $name && $in_target{$_} } keys %$o;
  die "нет вариантной группы $name в цели $app\n" unless $id; return $id }

sub add_ru { my ($group, $path, $type) = @_;
  my $id = new_id($path);
  $o->{$id} = { isa => 'PBXFileReference', lastKnownFileType => $type, name => 'ru',
                path => $path, sourceTree => '<group>' };
  push @{ $o->{$group}{children} }, $id; return $id }

push @{ $root->{knownRegions} }, 'ru' unless grep { $_ eq 'ru' } @{ $root->{knownRegions} };

add_ru(variant('Main.html'),       'ru.lproj/Main.html',    'text.html');
my $storyboard = variant('Main.storyboard');
add_ru($storyboard,                'ru.lproj/Main.strings', 'text.plist.strings');

# InfoPlist.strings: новой вариантной группы нет — заводим рядом со
# storyboard, в той же папке, и добавляем в Resources цели.
my ($parent) = grep { ($o->{$_}{isa} // '') eq 'PBXGroup' && grep { $_ eq $storyboard } @{ $o->{$_}{children} } } keys %$o;
die "не нашёл группу со storyboard\n" unless $parent;
my $vg = new_id('InfoPlist.strings group');
$o->{$vg} = { isa => 'PBXVariantGroup', name => 'InfoPlist.strings', children => [], sourceTree => '<group>' };
push @{ $o->{$parent}{children} }, $vg;
add_ru($vg, 'ru.lproj/InfoPlist.strings', 'text.plist.strings');
my $bf = new_id('InfoPlist.strings in Resources');
$o->{$bf} = { isa => 'PBXBuildFile', fileRef => $vg };
push @{ $o->{$resources}{files} }, $bf;

print JSON::PP->new->canonical->encode($data);
