package Yukki::Web;
use Moose;

extends qw( Yukki );

use Yukki::Error;
use Yukki::Web::Request;
use Yukki::Web::Router;

use HTTP::Throwable::Factory qw( http_throw http_exception );
use Scalar::Util qw( blessed );
use Try::Tiny;

=head1 NAME

Yukki::Web - the Yukki web-server

=cut

has router => (
    is          => 'ro',
    isa         => 'Path::Router',
    required    => 1,
    lazy_build  => 1,
);

sub _build_router {
    my $self = shift;
    Yukki::Web::Router->new( app => $self );
}

sub component {
    my ($self, $type, $name) = @_;
    my $class_name = join '::', 'Yukki::Web', $type, $name;
    Class::MOP::load_class($class_name);
    return $class_name->new(app => $self);
}

sub controller { 
    my ($self, $name) = @_;
    return $self->component(Controller => $name);
}

sub view {
    my ($self, $name) = @_;
    return $self->component(View => $name);
}

sub dispatch {
    my ($self, $env) = @_;

    my $response;
    try {
        my $req = Yukki::Web::Request->new(env => $env);
        my $match = $self->router->match($req->path);

        http_throw('NotFound') unless $match;

        $req->path_parameters($match->mapping);

        my $controller = $match->target;

        $response = $controller->fire($req);
    }

    catch {
        if (blessed $_ and $_->isa('Moose::Object') and $_->does('HTTP::Throwable')) {
            $response = $_->as_psgi($env);
        }

        else {
            warn "ISE: $_";

            $response = http_exception('InternalServerError', {
                show_stack_trace => 0,
            })->as_psgi($env);
        }
    };

    return $response;
}

1;