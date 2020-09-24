#!perl
use lib '.';
use t::Helper;
use t::Server::Irc;
use Mojo::IOLoop;
use Convos::Core;

my $server     = t::Server::Irc->new->start;
my $core       = Convos::Core->new(backend => 'Convos::Core::Backend');
my $user       = $core->user({email => 'superman@example.com'});
my $connection = $user->connection({name => 'localhost', protocol => 'irc'});

$server->client($connection)->server_event_ok('_irc_event_nick')->server_write_ok(['welcome.irc'])
  ->client_event_ok('_irc_event_rpl_welcome')->process_ok('welcome');

my (@messages, @state);
$connection->on(message => sub { push @messages, $_[2] });
$connection->on(state   => sub { push @state, [@_[1, 2]] });

note 'error handlers';
$server->server_write_ok(":localhost 404 superman #nopechan :Cannot send to channel\r\n")
  ->client_event_ok('_irc_event_err_cannotsendtochan')
  ->server_write_ok(":localhost 421 superman cool_cmd :Unknown command\r\n")
  ->client_event_ok('_irc_event_err_unknowncommand')
  ->server_write_ok(":localhost 432 superman nopeman :Erroneous nickname\r\n")
  ->client_event_ok('_irc_event_err_erroneusnickname')
  ->server_write_ok(":localhost 433 superman nopeman :Nickname is already in use\r\n")
  ->client_event_ok('_irc_event_err_nicknameinuse')
  ->server_write_ok(":localhost PING irc.example.com\r\n")->client_event_ok('_irc_event_ping')
  ->server_write_ok(":localhost PONG irc.example.com\r\n")->client_event_ok('_irc_event_pong')
  ->server_write_ok(":superwoman!Superduper\@localhost QUIT :Gone to lunch\r\n")
  ->client_event_ok('_irc_event_quit')->process_ok('error handlers');

is delete $_->{from}, 'irc-localhost', 'from irc-localhost' for @messages;
is delete $_->{type}, 'error',         'type error'         for @messages;
ok delete $_->{ts}, 'got timestamp' for @messages;

is_deeply(
  [map { $_->{message} } @messages],
  [
    'Cannot send to channel #nopechan.',
    'Unknown command: cool_cmd',
    'Invalid nickname nopeman.',
    'Nickname nopeman is already in use.',
  ],
  'got error messages',
);

is_deeply(
  \@state,
  [[me => {nick => 'nopeman_'}], [quit => {message => 'Gone to lunch', nick => 'superwoman'}]],
  'got state changes',
);

@state = ();
$server->server_write_ok(
  ":supergirl!u2\@example.com PRIVMSG mojo_irc :\x{1}PING 1393007660\x{1}\r\n")
  ->client_event_ok('_irc_event_ctcp_ping')->server_event_ok('_irc_event_ctcpreply_ping')
  ->server_write_ok(":supergirl!u2\@example.com PRIVMSG mojo_irc :\x{1}TIME\x{1}\r\n")
  ->client_event_ok('_irc_event_ctcp_time')->server_event_ok('_irc_event_ctcpreply_time')
  ->server_write_ok(":supergirl!u2\@example.com PRIVMSG mojo_irc :\x{1}VERSION\x{1}\r\n")
  ->client_event_ok('_irc_event_ctcp_version')->server_event_ok('_irc_event_ctcpreply_version')
  ->server_write_ok(":supergirl!u2\@example.com PRIVMSG superman :\x{1}ACTION msg1\x{1}\r\n")
  ->client_event_ok('_irc_event_ctcp_action')->process_ok('basic commands');
is_deeply \@state, [], 'basic commands does not cause events';

@state = ();
$connection->dialog({name => '#convos'});
$server->server_write_ok(":localhost 004 superman hybrid8.debian.local hybrid-")
  ->server_write_ok(
  "1:8.2.0+dfsg.1-2 DFGHRSWabcdefgijklnopqrsuwxy bciklmnoprstveIMORS bkloveIh\r\n")
  ->client_event_ok('_irc_event_rpl_myinfo')
  ->server_write_ok(":superwoman!sw\@localhost JOIN :#convos\r\n")
  ->client_event_ok('_irc_event_join')
  ->server_write_ok(":superwoman!sw\@localhost KICK #convos superwoman :superman\r\n")
  ->client_event_ok('_irc_event_kick')
  ->server_write_ok(":superman!sm\@localhost MODE #convos +i :superwoman\r\n")
  ->client_event_ok('_irc_event_mode')
  ->server_write_ok(":supergirl!sg\@localhost NICK :superduper\r\n")
  ->client_event_ok('_irc_event_nick')
  ->server_write_ok(":superduper!sd\@localhost PART #convos :I'm out\r\n")
  ->client_event_ok('_irc_event_part')
  ->server_write_ok(":superwoman!sw\@localhost TOPIC #convos :Too cool!\r\n")
  ->client_event_ok('_irc_event_topic')->process_ok('channel commands');

cmp_deeply(
  \@state,
  bag(
    [join => {dialog_id => '#convos', nick => 'superwoman'}],
    [mode => {dialog_id => '#convos', from => 'superman', mode => '+i', nick => 'superwoman'}],
    [nick_change => {new_nick  => 'superduper', old_nick => 'supergirl'}],
    [part        => {dialog_id => '#convos',    message  => 'I\'m out', nick => 'superduper'}],
    [
      me => {
        available_channel_modes => 'bciklmnoprstveIMORS',
        available_user_modes    => 'DFGHRSWabcdefgijklnopqrsuwxy',
        nick                    => 'superman',
        real_host               => 'hybrid8.debian.local',
        version                 => 'hybrid-1:8.2.0+dfsg.1-2',
      }
    ],
    [
      part => {
        dialog_id => '#convos',
        kicker    => 'superwoman',
        message   => 'superman',
        nick      => 'superwoman',
      }
    ],
    [
      frozen => {
        connection_id => 'irc-localhost',
        dialog_id     => '#convos',
        frozen        => '',
        name          => '#convos',
        topic         => 'Too cool!',
        unread        => 0,
      }
    ]
  ),
  'state changes',
) or diag explain \@state;

@messages = ();
$server->server_write_ok(":localhost NOTICE AUTH :*** Found your hostname\r\n")
  ->client_event_ok('_irc_event_notice')->process_ok('notice');

cmp_deeply(
  \@messages,
  bag(
    map {
      +{
        highlight => false,
        from      => 'irc-localhost',
        message   => $_,
        ts        => re(qr{^\d+}),
        type      => 'notice',
      };
    } '*** Found your hostname'
  ),
  'got noticed',
) or diag explain \@messages;

is $connection->{failed_to_connect}, 0, 'failed_to_connect = 0';
$server->server_write_ok("ERROR :Trying to reconnect too fast.\r\n")
  ->client_event_ok('_irc_event_error')->process_ok('error');
is $connection->{failed_to_connect}, 1, 'failed_to_connect = 1';

{
  no warnings 'redefine';
  my $delay;
  local *Mojo::IOLoop::timer = sub { $delay = $_[1]; Mojo::IOLoop->stop; };
  $server->close_connections;
  Mojo::IOLoop->start;
  is $delay, 8, 'delayed reconnect';
}

done_testing;
