package Convos::Plugin::Video;
use Mojo::Base 'Convos::Plugin';

use Convos::Plugin::Video::Dialog;

sub register {
  my ($self, $app, $config) = @_;

  $app->routes->get('/live/:vid')->to(cb => sub { $self->_render(@_) });

  # Upgrade message to video chat
  $app->core->backend->on(message_to_video => 'Convos::Plugin::Video::Dialog');
}

sub _events {
  my ($self, $c) = @_;
}

sub _render {
  my ($self, $c) = @_;
  return $self->_events($c) if $c->tx->is_websocket;

  $c->res->headers->header('X-Provider-Name', 'ConvosVideo');

  my $dialog = Convos::Plugin::Video::Dialog->new(core => $c->app->core, id => $c->stash('vid'));
  return $dialog->load_p->then(sub {
    return $c->reply->not_found unless eval { $dialog->name };    # invalid vid

    my $settings = $c->stash->{meta_settings} ||= {};
    $settings->{dialog_name} = $dialog->name;

    $c->render('video/index', chat => $dialog);
  });
}

1;

=encoding utf8

=head1 NAME

Convos::Plugin::Video - Video chat for Convos

=head1 DESCRIPTION

L<Convos::Plugin::Video> enables L<Convos> to generate and handle video chat
links.

=head1 METHODS

=head2 register

  $bot->register($app, \%config);

Will set up route for "/live/:vid" and "message_to_video" event.

=head1 SEE ALSO

L<Convos>, L<Convos::Plugin::Video::Dialog>.

=cut
