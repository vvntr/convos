package Convos::Plugin::Video::Dialog;
use Mojo::Base -base;

use Carp 'confess';
use Convos::Util qw(generate_secret short_checksum);
use Mojo::Path;
use Mojo::Util qw(url_escape);

has core          => sub { confess 'core() required in constructor' };
has connection_id => sub { confess 'connection_id() required in constructor' };
has created       => sub { Mojo::Date->new->to_datetime };
has dialog_id     => sub { confess 'dialog_id() required in constructor' };
has id            => \&_build_id;
has name          => sub { confess 'name() required in constructor' };

sub handle_message_to_video_p {
  my ($class, $backend, $connection, $dialog_id, $name) = @_;

  my $dialog = $connection->get_dialog($dialog_id);
  my $self   = $class->new(
    core          => $connection->user->core,
    connection_id => $connection->id,
    dialog_id     => $dialog->id,
    name          => $name || $dialog->name,
  );

  if ($name) {
    my $id = lc $name;
    $id =~ s!\W!-!g;
    $self->id(join '-', $connection->user->uid, $id);
  }

  return $self->load_p->then(sub { 0 && $self->{created} ? $self : $self->save_p });
}

sub load_p {
  my $self = shift;
  return $self->core->backend->load_object_p($self)->then(sub { $self->_parse_attrs(shift) });
}

sub public_url { $_[0]->core->web_url(join '/', 'live', $_[0]->id)->to_abs }
sub save_p     { $_[0]->core->backend->save_object_p($_[0]) }
sub to_message { shift->public_url->to_string }
sub uri        { Mojo::Path->new(sprintf 'video/%s.json', shift->id) }

sub _build_id {
  my $self = shift;
  short_checksum join ':', $self->core->settings->session_secrets->[0], $self->connection_id,
    $self->dialog_id;
}

sub _parse_attrs {
  my ($self, $attrs) = @_;
  $self->$_($attrs->{$_}) for grep { $attrs->{$_} } qw(connection_id created dialog_id id name);
  return $self;
}

sub TO_JSON {
  my ($self, $persist) = @_;
  my $json = {};

  $json->{$_} = $self->$_ for qw(connection_id created dialog_id id name);
  $json->{url} = $self->public_url->to_string unless $persist;

  return $json;
}

1;

=encoding utf8

=head1 NAME

Convos::Plugin::Video::Dialog - Represents a video chat

=head1 DESCRIPTION

L<Convos::Plugin::Video::Dialog> is a class used by represent a video chat.

=head1 ATTRIBUTES

=head2 core

=head2 connection_id

=head2 created

=head2 dialog_id

=head2 id

=head2 name

=head1 METHODS

=head2 handle_message_to_video_p

=head2 load_p

=head2 public_url

=head2 save_p

=head2 to_message

=head2 uri

=head1 SEE ALSO

L<Convos>, L<Convos::Plugin::Video>.

=cut
