#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

use File::Temp qw(tempfile);
use FindBin qw($Bin);
use DBI;

use Potracheno::Model;

my $spec = "$Bin/../sql/potracheno.sqlite.sql";

my $sql = do {
    open (my $fd, "<", $spec)
        or die "Failed to load sqlite schema $spec: $!";
    local $/;
    <$fd>
};

my (undef, $dbfile) = tempfile;
my $fail;
$SIG{__DIE__} = sub { $fail++ };
END {
    if ($fail) {
        diag "Tests failed, db available at $dbfile"
    } else {
        unlink $dbfile;
    };
};

my $db = "dbi:SQLite:dbname=$dbfile";
my $dbh = DBI->connect( $db, '', '', { RaiseError => 1 } );

$dbh->do( $_ ) for split /;/, $sql; # this autodies
$dbh->disconnect;

my $model = Potracheno::Model->new(
    db_handle => $db,
);

# Huh, let the tests begin
note "TESTING USER";

my $user = $model->get_user( name => "Foo" );

is ($user->{user_id}, 1, "1st user on a clean db" );
is ($user->{name}, "Foo", "Input round trip" );

$user = $model->get_user( name => "Bar" );

is ($user->{user_id}, 2, "2nd user on a clean db" );
is ($user->{name}, "Bar", "Input round trip (2)" );

$user = $model->get_user( name => "Foo" );
is ($user->{user_id}, 1, "Fetching 1st user again" );
is ($user->{name}, "Foo", "Input round trip(3)" );

note explain $user;

note "TESTING ARTICLE";

my $id = $model->add_article( body => "++", summary => "+", user => $user );

my $art = $model->get_article( id => $id );

is ($art->{author}, "Foo", "Author as expected");
is ($art->{body}, "++", "Round-trip - body");
is ($art->{summary}, "+", "Round-trip - summary");
is ($art->{time_spent}, 0, "0 time spent");

note explain $art;

note "TESTING TIME";

$model->add_time( article_id => $art->{article_id}, user_id => 1, time => 1 );
$model->add_time( article_id => $art->{article_id}, user_id => 2, time => 2 );

$art = $model->get_article( id => $id );
is ($art->{time_spent}, 3, "3 time spent");

done_testing;
