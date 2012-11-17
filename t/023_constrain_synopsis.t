#-*-perl-*-
#$Id: 022_constrain.t 10 2012-11-12 03:13:39Z maj $#
use Test::More qw(no_plan);
use Test::Exception;
use File::Temp qw(tempfile);
use Module::Build;
use lib '../lib';

use REST::Neo4p;
use REST::Neo4p::Constrain qw(:all);

use warnings;
no warnings qw(once);
$SIG{__DIE__} = sub { die $_[0] };
my @cleanup;

my $build;
eval {
  $build = Module::Build->current;
};
my $TEST_SERVER = $build ? $build->notes('test_server') : 'http://127.0.0.1:7474';
my $num_live_tests = 1;

my $not_connected;
eval {
  REST::Neo4p->connect($TEST_SERVER);
};
if ( my $e = REST::Neo4p::CommException->caught() ) {
  $not_connected = 1;
  diag "Test server unavailable : ".$e->message;
}

SKIP : {
  skip 'no local connection to neo4j, live tests not performed', $num_live_tests if $not_connected;
 
 # create some constraints
 
  ok create_constraint (
    tag => 'owner',
    type => 'node_property',
    condition => 'only',
    constraints => {
      name => qr/[a-z]+/i,
      species => 'human'
     }
   ), 'create constraint 1';
  
  ok create_constraint(
    tag => 'pet',
    type => 'node_property',
    condition => 'all',
    constraints => {
      name => qr/[a-z]+/i,
      species => qr/^dog|cat|ferret|mole rat|platypus$/
     }
   ), 'create constraint 2';
  
  ok create_constraint(
    tag => 'owners2pets',
    type => 'relationship',
    rtype => 'OWNS',
    constraints =>  [{ owner => 'pet' }] # note arrayref
   ),'create constraint 3';
  
  ok create_constraint(
    tag => 'allowed_rtypes',
    type => 'relationship_type',
    constraints => [qw( OWNS FEEDS LOVES )]
   ),'create constraint 4';
  
  ok create_constraint(
    tag => 'ignore',
    type => 'relationship',
    rtype => 'IGNORES',
    constraints =>  [{ pet => 'owner' },
		     { owner => 'pet' }] # both directions ok
   ), 'create constraint 5';

  # constrain by automatic exception-throwing
  
  ok constrain(), 'constrain()';
  
  ok my $fred = REST::Neo4p::Node->new( { name => 'fred', species => 'human' } ), 'fred';
  push @cleanup, $fred if $fred;
  ok my $fluffy = REST::Neo4p::Node->new( { name => 'fluffy', species => 'mole rat' } ), 'fluffy';
  push @cleanup, $fluffy if $fluffy;

  ok my $r1 = $fred->relate_to($fluffy, 'OWNS'), 'reln 1 is valid,created';
  push @cleanup, $r1 if $r1;
  my $r2;

  throws_ok { $r2 = $fluffy->relate_to($fred, 'OWNS') } 'REST::Neo4p::ConstraintException', 'constrained';
  push @cleanup, $r2 if $r2;
  my $r3;
  throws_ok { $r3 = $fluffy->relate_to($fred, 'IGNORES') } 'REST::Neo4p::ConstraintException', 'constrained';

 # allow relationship types that are not explictly
 # allowed -- a relationship constraint is still required

 $REST::Neo4p::Constraint::STRICT_RELN_TYPES = 0;

  ok $r3 = $fluffy->relate_to($fred, 'IGNORES'), 'relationship types relaxed, create reln';
  push @cleanup, $r3 if $r3;

  ok relax(), 'relax'; # stop automatic constraints

  # use validation

  ok $r2 = $fluffy->relate_to($fred, 'OWNS'),'relaxed, invalid relationship created'; # not valid, but auto-constraint not in force
  push @cleanup, $r2 if $r2;
  ok validate_properties($r2), 'r2 properties are valid';
  ok !validate_relationship($r2), 'r2 is invalid';
  # try a relationship
  ok validate_relationship( $fred => $fluffy, 'LOVES' ), 'fred LOVES fluffy valid';
  # try a relationship type
  ok !validate_relationship( $fred => $fluffy, 'EATS' ), 'relationship type not valid';
 # serialize all constraints
  my ($tmpfh, $tmpf) = tempfile();
  print $tmpfh serialize_constraints();
  close $tmpfh;
  
  # remove current constraints
  my %c = REST::Neo4p::Constraint->get_all_constraints;
  while ( my ($tag, $constraint) = 
	    each %c ) {
    ok $constraint->drop, "constraint dropped";
  }
  
  # restore constraints
  open $tmpfh,$tmpf;
  local $/ = undef;
  my $json = <$tmpfh>;
  ok load_constraints($json), 'load constraints';
  %c = REST::Neo4p::Constraint->get_all_constraints;
  is scalar values %c, 5, 'got back constraints';
  close $tmpfh;
  unlink $tmpf;
}

END {
  CLEANUP : {
    ok ($_->remove,'entity removed') for reverse @cleanup;
  }
  }
