#!/usr/bin/env perl

use strict;
use warnings;
our $VERSION = 0.0103;

use URI::Escape;
use Data::Dumper;
use POSIX qw(strftime);

use FindBin qw($Bin);
use File::Basename qw(dirname);
use lib "$Bin/../lib";
use MVC::Neaf 0.0702;
use MVC::Neaf::Exception qw(neaf_err);
use Potracheno::Model;

# Will consume config later
my $model = Potracheno::Model->new(
    db_handle => "dbi:SQLite:dbname=$Bin/../nocommit-data/potracheno.sqlite",
);

MVC::Neaf->load_view( TT => TT =>
    INCLUDE_PATH => "$Bin/../tpl",
    PRE_PROCESS  => "common_head.tt",
    POST_PROCESS => "common_foot.tt",
    EVAL_PERL => 1,
)->render({ -template => \"\n\ntest\n\n" });

MVC::Neaf->set_default( HTML => \&HTML, URI => \&URI, DATE => \&DATE
    , copyright_by => "Lodin" );

MVC::Neaf->set_session_handler( engine => $model, view_as => 'session' );

MVC::Neaf->route( login => sub {
    my $req = shift;

    my $name = $req->param( name => '\w+' );
    my $pass = $req->param( pass => '.+' );
    my $data;
    my $wrong;
    if ($req->method eq 'POST' and $name and $pass) {
        $data = $model->login( $name, $pass );
        $wrong = "Login failed!";
    };
    if ($data) {
        warn "LOGIN SUCCESSFUL!!!";
        $req->save_session( $data );
        $req->redirect( $req->param( return_to => '/.*', '/') );
    };

    return {
        -template => 'login.html',
        wrong => $wrong,
        name => $name,
    };
} );

MVC::Neaf->route( logout => sub {
    my $req = shift;

    $req->delete_session;
    $req->redirect( $req->referer || '/' );
});

MVC::Neaf->route( register => sub {
    my $req = shift;

    my $user = $req->param( user => '\w+' );
    if ($req->method eq 'POST') {
        eval {
            $user or die "FORM: [User must be nonempty alphanumeric]";
            my $pass  = $req->param( pass  => '.+' );
            $pass or die "FORM: [Password empty]";
            my $pass2 = $req->param( pass2 => '.+' );
            $pass eq $pass2 or die "FORM: [Passwords do not match]";

            my $id = $model->add_user( $user, $pass );
            $id   or die "FORM: [Username '$user' already taken]";

            $req->session->{user_id} = $id;
            $req->redirect("/");
        };
        neaf_err($@);
    };

    my ($wrong) = $@ =~ /^FORM:\s*\[(.*)\]/;

    return {
        -template => 'register.html',
        user => $user,
        wrong => $wrong,
    };
});

# fetch usr
# model.add article
# returnto view
MVC::Neaf->route( post => sub {
    my $req = shift;

    my $user     = $req->session;

    if ( $req->method ne 'POST' ) {
        return {
            -template => "post.html",
            title => "Submit new article",
        };
    };

    # Switch to form?
    my $summary  = $req->param( summary => qr/\S.+\S/ );
    my $body     = $req->param( body => qr/.*\S.+/ );

    die 403 unless $user->{user_id};
    die 422 unless $summary and $body;

    my $id = $model->add_article( user => $user, summary => $summary, body => $body );
    $req->redirect( "/article/$id" );
} );

MVC::Neaf->route( article => sub {
    my $req = shift;

    my $id = $req->path_info =~ /(\d+)/ ? $1 : $req->param ( id => '\d+' );
    die 422 unless $id;

    my $data = $model->get_article( id => $id );
    die 404 unless $data->{article_id};
    warn Dumper($data);

    my $comments = $model->get_comments( article_id => $id, sort => '+posted' );

    return {
        -template => "article.html",
        title => "#$data->{article_id} - $data->{summary}",
        article => $data,
        comments => $comments,
    };
} );

MVC::Neaf->route( search => sub {
    my $req = shift;

    my $q = $req->param(q => '.*');

    my @term = $q =~ /([\w*?]+)/g;

    my $result = $model->search(terms => \@term);

    return {
        -template => 'search.html',
        title => "Search results for @term",
        results => $result,
        q => $q,
        terms => \@term,
    };
} );

# fetch usr
# model. add time
# return to view
MVC::Neaf->route( addtime => sub {
    my $req = shift;

    my $user = $req->session;
    die 403 unless $user;

    # TODO use form!!!!
    my $article_id = $req->param( article_id => qr/\d+/ );
    my $seconds  = $req->param( seconds => qr/\d+/, 0 );
    my $note     = $req->param( note => qr/.*\S.+/ );

    die 422 unless $article_id;

    $model->add_time( article_id => $article_id, user_id => $user->{user_id}
        , time => $seconds, note => $note);

    $req->redirect( "/article/$article_id" );
}, method => "POST" );

MVC::Neaf->route( user => sub {
    my $req = shift;

    my $id = $req->param( user_id => '\d+', $req->path_info =~ /(\d+)/ );
    my $data = $model->load_user ( user_id => $id );
    die 404 unless $data->{user_id};

    my $comments = $model->get_comments( user_id => $id, sort => '-posted' );
    return {
        -template => 'user.html',
        title => "$data->{name} - user details",
        user => $data,
        comments => $comments,
    };
});

MVC::Neaf->route( "/" => sub {
    my $req = shift;

    # this is main page ONLY
    die 404 if $req->path_info gt '/';

    return {
        title => "Potracheno - wasted time tracker",
        -template => "main.html",
    };
} );

my %replace = qw( & &amp; < &gt; > &gt; " &qout; );
my $bad_chars = join "", map { quotemeta $_ } keys %replace;
$bad_chars = qr/([$bad_chars])/;

sub HTML {
    my $str = shift;
    $str =~ s/$bad_chars/$replace{$1}/g;
    return $str;
};

sub URI {
    my $str = shift;
    return uri_escape_utf8($str);
};

sub DATE {
    my $time = shift;
    return strftime("%Y-%m-%d %H:%M:%S", localtime($time));
};

MVC::Neaf->run();
