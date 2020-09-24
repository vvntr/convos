#!perl
BEGIN {
  our $time = time - 10;
  *CORE::GLOBAL::time = sub {$time};
}
use lib '.';
use t::Helper;
use Convos::Core;
use Convos::Core::Backend::File;

no warnings qw(once redefine);

my $core = Convos::Core->new(backend => 'Convos::Core::Backend::File');

note 'trim and lower case';
my $user          = $core->user({email => ' JhtHorsen@cpan.org  '});
my $settings_file = File::Spec->catfile($ENV{CONVOS_HOME}, 'jhthorsen@cpan.org', 'user.json');
is $user->email,    'jhthorsen@cpan.org', 'email';
is $user->password, '',                   'password';

ok !-e $settings_file, 'no storage file';
$user->save_p->$wait_success('save_p');
ok -e $settings_file, 'created storage file';

is_deeply(
  $user->TO_JSON,
  {
    email              => 'jhthorsen@cpan.org',
    highlight_keywords => [],
    registered         => Mojo::Date->new($main::time)->to_datetime,
    roles              => [],
    uid                => 1,
    unread             => 0
  },
  'TO_JSON'
);

note 'password';
eval { $user->set_password('') };
like $@, qr{Usage:.*plain}, 'set_password() require plain string';
ok !$user->password, 'no password';
is $user->set_password('s3cret'), $user, 'set_password does not care about password quality';
ok $user->password, 'password';

ok !$user->validate_password('s3crett'), 'invalid password';
ok $user->validate_password('s3cret'), 'validate_password';

$user->save_p->$wait_success('save_p');
is $core->get_user('jhthorsen@cpan.org')->password, $user->password, 'password from storage file';

note 'unread';
$user->{unread} = 3;
$user->save_p->$wait_success('save_p');
is $core->get_user('jhthorsen@cpan.org')->unread, 3, 'Unseen is persisted correctly';

note 'users order';
$main::time++;
$core->user({email => 'aaa@bbb.com'})->save_p->$wait_success('save_p');
$core->user({email => 'bbb@bbb.com', registered => '1983-02-24T01:23:00Z'})
  ->save_p->$wait_success('save_p');
$core->user({email => 'ccc@bbb.com'})->save_p->$wait_success('save_p');

my $users;
$core->backend->users_p->then(sub { $users = shift })->$wait_success('users_p');
is_deeply(
  [map { $_->{email} } @$users],
  [qw(bbb@bbb.com jhthorsen@cpan.org aaa@bbb.com ccc@bbb.com)],
  'got users in the right order',
);

note 'first registered user gets admin - bbb@bbb.com (back compat)';
$ENV{CONVOS_SKIP_CONNECT} = 1;
$user->roles([])->save_p->$wait_success('save_p');
undef $core;    # Fresh start
$core = Convos::Core->new(backend => 'Convos::Core::Backend::File');
$core->start;
Mojo::IOLoop->one_tick until $core->ready;
is_deeply(
  {map { ($_->email => $_->roles) } @{$core->users}},
  {
    'bbb@bbb.com'        => ['admin'],
    'jhthorsen@cpan.org' => [],
    'aaa@bbb.com'        => [],
    'ccc@bbb.com'        => [],
  },
  'first registered user gets to be admin'
);

done_testing;
