#!perl
use lib '.';
use Convos::Util qw(short_checksum);
use t::Helper;
use t::Server::Irc;

my $server = t::Server::Irc->new->start;
my $t      = t::Helper->t;

my $user = $t->app->core->user({email => 'superman@example.com'})->set_password('s3cret');
$t->post_ok('/api/user/login', json => {email => 'superman@example.com', password => 's3cret'})
  ->status_is(200);

my $connection = $user->connection({name => 'localhost', protocol => 'irc'});
$connection->dialog({name => '#Convos'});
$server->client($connection)->server_event_ok('_irc_event_nick')->server_write_ok(['welcome.irc'])
  ->client_event_ok('_irc_event_rpl_welcome')->process_ok;

$t->get_ok('/video')->status_is(404);
$t->get_ok('/video/1/jLF03N1TBgKAqCZg')->status_is(404);
$t->get_ok('/video/1/1-myvideochat')->status_is(404);

note 'missing input';
my %send = (connection_id => $connection->id, message => '/video', method => 'send');
$t->websocket_ok('/events')->send_ok({json => \%send})
  ->message_ok->json_message_is('/errors/0/message', 'Cannot send without target.');

note 'create video chat';
$send{dialog_id} = '#convos';
$t->send_ok({json => \%send})->message_ok->json_message_is('/event', 'message')
  ->json_message_like('/message', qr{/live/\w+$});
$t->finish_ok;

my $url = url_from_message();
isnt $url->path->[-1], short_checksum('irc-localhost:#convos'),
  'default ID need to mix in a secret';
$t->get_ok($url)->status_is(200)->element_exists(qq(meta[name="convos:start"][content="video"]))
  ->element_exists(qq(meta[name="convos:status"][content="200"]))
  ->element_exists(qq(meta[name="convos:dialog_name"][content="#Convos"]))
  ->element_exists(
  qq(meta[name="description"][content^="Video chat with #Convos. Do you want to join the conversation?"])
)->text_is('title', 'Video chat with #Convos - Convos')->element_exists('.convos-video-chat')
  ->text_is('.convos-video-chat h1', 'Video chat with #Convos')
  ->text_like('.convos-video-chat p', qr{Starting video chat});

note 'reuse existing vid';
$t->websocket_ok('/events')->send_ok({json => \%send})
  ->message_ok->json_message_is('/event', 'message')->json_message_is('/message', $url->to_string);
$t->finish_ok;

note 'custom name';
$send{message} = '/video MyVideoChat';
$t->websocket_ok('/events')->send_ok({json => \%send})
  ->message_ok->json_message_is('/event', 'message')
  ->json_message_like('/message', qr{/live/1-myvideochat});
$url = url_from_message();
$t->finish_ok;
$t->get_ok($url)->status_is(200)
  ->element_exists(qq(meta[name="convos:dialog_name"][content="MyVideoChat"]))
  ->element_exists('.convos-video-chat')
  ->text_is('.convos-video-chat h1', 'Video chat with MyVideoChat')
  ->text_like('.convos-video-chat p', qr{Starting video chat});

done_testing;

sub url_from_message {
  my $msg = Mojo::JSON::decode_json($t->message->[1]);
  return Mojo::URL->new($msg->{message});
}
