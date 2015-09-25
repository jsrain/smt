package SMT::Rest::SCCAPIv4;

require SMT::Rest::SCCAPIv3;
@ISA = qw(SMT::Rest::SCCAPIv3);

use strict;
use Apache2::Const -compile => qw(:log OK SERVER_ERROR HTTP_NO_CONTENT AUTH_REQUIRED FORBIDDEN HTTP_UNPROCESSABLE_ENTITY HTTP_UNAUTHORIZED);

use JSON;

use SMT::Utils;
use SMT::Client;
use SMT::Registration;


sub new
{
    my($class, $r) = @_;
    my $self = $class->SUPER::new($r);

    return $self;
}

sub systems_handler()
{
    my $self = shift;
    my ($code, $data) = (undef, undef);

    ($code, $data) = $self->SUPER::systems_handler();
    if (!defined $code && !defined $data)
    {
        my $path = $self->sub_path();

        if     ( $self->request()->method() =~ /^GET$/i )
        {
        }
        elsif ( $self->request()->method() =~ /^POST$/i )
        {
            if     ( $path =~ /^systems\/products\/migrations\/?$/ ) { return $self->product_migration_targets(); }
            elsif  ( $path =~ /^systems\/products\/synchronize\/?$/ ) { return $self->product_synchronize(); }
        }
        elsif ( $self->request()->method() =~ /^PUT$/i || $self->request()->method() =~ /^PATCH$/i)
        {
        }
        elsif ( $self->request()->method() =~ /^DELETE$/i )
        {
        }
     }
     return ($code, $data);
}

sub product_synchronize
{
    my $self = shift || return (undef, undef);
    my $c    = JSON::decode_json($self->read_post());
    my $guid = $self->user();
    my $installedProducts = [];
    my $result = [];

    foreach my $installedProduct (@{$c->{products}})
    {
        if ( ! (exists $installedProduct->{identifier} && $installedProduct->{identifier}))
        {
            return (Apache2::Const::HTTP_UNPROCESSABLE_ENTITY, "Missing required parameter: identifier");
        }
        if ( ! (exists $installedProduct->{version} && $installedProduct->{version}))
        {
            return (Apache2::Const::HTTP_UNPROCESSABLE_ENTITY, "Missing required parameter: version");
        }
        else
        {
            # sometimes people provide edition instead of version, so let's stip the release
            my ($v, $r) = split(/-/, $installedProduct->{version}, 2);
            $installedProduct->{version} = $v;
        }
        if ( ! (exists $installedProduct->{arch} && $installedProduct->{arch}))
        {
            return (Apache2::Const::HTTP_UNPROCESSABLE_ENTITY, "Missing required parameter: arch");
        }
        if ( ! (exists $installedProduct->{release_type}))
        {
            $installedProduct->{release_type} = undef;
        }
        push @{$installedProducts}, $installedProduct;
    }
    my $statement = sprintf("SELECT p.id id,
                                    p.PRODUCT identifier,
                                    p.VERSION version,
                                    p.REL release_type,
                                    p.ARCH arch,
                                    p.FRIENDLY friendly_name
                               FROM Products p
                               JOIN Registration r ON r.PRODUCTID = p.ID
                              WHERE r.GUID=%s",
                            $self->dbh()->quote($guid));
    my $registeredProducts = $self->dbh()->selectall_arrayref($statement, {Slice => {}});
    foreach my $regProd (@{$registeredProducts})
    {
        my $found = 0;
        foreach my $instProd (@{$installedProducts})
        {
            if( $regProd->{'identifier'} eq $instProd->{'identifier'} &&
                $regProd->{'version'} eq $instProd->{'version'} &&
                $regProd->{'arch'} eq $instProd->{'arch'})
            {
                # extra check for REL
                if( ! $regProd->{'release_type'} ||
                    $regProd->{'release_type'} eq $instProd->{'release_type'})
                {
                    $found = 1;
                    last;
                }
            }
        }
        if( ! $found )
        {
            $self->_deregister_product($guid, $regProd);
            $self->request()->log->warn(sprintf("Product '%s' de-activated", $regProd->{friendly_name}));
        }
        else
        {
             push @{$result}, $self->_getProduct($regProd->{id});
        }
    }
    return (Apache2::Const::OK, $result);
}

sub product_migration_targets
{
    my $self = shift || return (undef, undef);
    my $c    = JSON::decode_json($self->read_post());
    my $currentProducts = [];
    my $guid = $self->user();
    my @not_registered_products = ();
    my $installedProducts = [];

    foreach my $installedProduct (@{$c->{installed_products}})
    {
        if ( ! (exists $installedProduct->{identifier} && $installedProduct->{identifier}))
        {
            return (Apache2::Const::HTTP_UNPROCESSABLE_ENTITY, "Missing required parameter: identifier");
        }

        if ( ! (exists $installedProduct->{version} && $installedProduct->{version}))
        {
            return (Apache2::Const::HTTP_UNPROCESSABLE_ENTITY, "Missing required parameter: version");
        }
        else
        {
            # sometimes people provide edition instead of version, so let's stip the release
            my ($v, $r) = split(/-/, $installedProduct->{version}, 2);
            $installedProduct->{version} = $v;
        }

        if ( ! (exists $installedProduct->{arch} && $installedProduct->{arch}))
        {
            return (Apache2::Const::HTTP_UNPROCESSABLE_ENTITY, "Missing required parameter: arch");
        }

        if ( ! (exists $installedProduct->{release_type}))
        {
            $installedProduct->{release_type} = undef;
        }
        my $productId = SMT::Utils::lookupProductIdByName($self->dbh(),
                                                          $installedProduct->{identifier},
                                                          $installedProduct->{version},
                                                          $installedProduct->{release_type},
                                                          $installedProduct->{arch});
        if(! SMT::Utils::hasClientProductRegistered($self->dbh(), $guid, $productId))
        {
            my $p = SMT::Utils::lookupProductById($self->dbh(), $productId);
            push @not_registered_products, $p->{friendly_name};
        }
        else
        {
            push @$installedProducts, $productId;
        }
    }
    if (@not_registered_products > 0)
    {
        return (Apache2::Const::HTTP_UNPROCESSABLE_ENTITY,
            sprintf("The requested products '%s' are not activated on the system.", join(', ', @not_registered_products)));
    }

    # now we can start to calculate the migration targets
    return $self->_calcMigrationTargets($installedProducts);
}

sub update_product
{
    my $self = shift || return (undef, undef);
    my $args = JSON::decode_json($self->read_post());
    my $product_classes = {};
    my $old_pdid = undef;

    if (!exists $args->{identifier} || !exists $args->{version} || !exists $args->{arch})
    {
        return (Apache2::Const::HTTP_UNPROCESSABLE_ENTITY, "No product specified");
    }
    my $former_identifier = $args->{identifier};

    # We are sure, that user is a system GUID
    my $guid = $self->user();

    # sometimes people provide edition instead of version, so let's stip the release
    my ($v, $r) = split(/-/, $args->{version}, 2);
    $args->{version} = $v;

    my $release = ((exists $args->{release_type})?$args->{release_type}:"");
    my $req_pdid = SMT::Utils::lookupProductIdByName($self->dbh(), $args->{identifier},
                                                     $args->{version}, $release,
                                                     $args->{arch}, $self->request());
    my $regs = SMT::Utils::lookupRegistrationByGUID($self->dbh(), $guid, $self->request());

    foreach my $cur_pid (keys %$regs)
    {
        if (SMT::Utils::isMigrationTargetOf($self->dbh(), $cur_pid, $req_pdid)    # upgrade
            || SMT::Utils::isMigrationTargetOf($self->dbh(), $req_pdid, $cur_pid) # Rollback
            || "$req_pdid" eq "$cur_pid" # same ; not an upgrade
        )
        {
            $old_pdid = $cur_pid;
            last ;
        }
    }

    if($old_pdid && $req_pdid)
    {
        if("$req_pdid" ne "$old_pdid")
        {
            my $sql = sprintf("UPDATE Registration
                                  SET PRODUCTID = %s
                                WHERE GUID = %s
                                  AND PRODUCTID = %s",
                              $self->dbh()->quote($req_pdid),
                              $self->dbh()->quote($guid),
                              $self->dbh()->quote($old_pdid));
            $self->request()->log->info("STATEMENT: $sql");
            eval {
                $self->dbh()->do($sql);
            };
            if($@)
            {
                return (Apache2::Const::SERVER_ERROR, "DBERROR: ".$self->dbh()->errstr);
            }
        }
    }
    else
    {
        return (Apache2::Const::HTTP_UNPROCESSABLE_ENTITY,
                "No installed product with requested migration target product found");
    }
    return $self->_registrationResult($req_pdid);
}


#################################################################################

sub _calcMigrationTargets
{
    my $self = shift || return (undef, undef);
    my $installedProducts = shift || return (undef, undef);

    my $expanded;
    my @result = ();
    printLog($self->request(), undef, LOG_DEBUG,
             "Search migration targets for: ".join(', ', @$installedProducts));

    foreach my $pdid (@$installedProducts)
    {
        my $targets = SMT::Utils::lookupMigrationTargetsById($self->dbh(), $pdid, $self->request());
        push @$targets, $pdid;
        $expanded = $self->_expandToPossibleTargets($targets, $expanded);
    }

    my $debugtext = "";
    foreach my $exset (@$expanded)
    {
        # remove solutions where source and target is the same
        if ( SMT::Utils::array_compare($installedProducts, $exset) )
        {
            printLog($self->request(), undef, LOG_DEBUG, "drop installed products combi");
            next;
        }
        $debugtext .= join(', ', @$exset)."\n";

        my @productset = ();
        foreach my $pdid (@$exset)
        {
            my $product = SMT::Utils::lookupProductById($self->dbh(), $pdid, $self->request());
            $product->{free} = ($product->{free}?JSON::true:JSON::false);
            $product->{available} = ($product->{available}?JSON::true:JSON::false);
            push @productset, $product;
        }
        push @result, \@productset;
    }
    printLog($self->request(), undef, LOG_DEBUG, "Migration Targets: $debugtext");

    return (Apache2::Const::OK, \@result);
}

sub _expandToPossibleTargets
{
    my $self = shift   || return [];
    my $array1 = shift || return [];
    my $array2 = shift || [[]];

    my @result = ();

    foreach my $set (@$array2)
    {
        foreach my $v1 (@$array1)
        {
            my @dummy = ();
            push @dummy, @$set, $v1;
            printLog($self->request(), undef, LOG_DEBUG, "Check combi: ".join(', ', @dummy));
            if ($self->_possibleTarget(@dummy))
            {
                printLog($self->request(), undef, LOG_DEBUG, "found possible combi");
                push @result, \@dummy;
            }
        }
    }
    return \@result;
}

sub _possibleTarget
{
    my $self = shift   || return 0;
    my @possibleTarget = @_;

    my $pset = [];
    my $compat = [shift @possibleTarget];
    #push @$pset, @possibleTarget;
    $pset = \@possibleTarget;
    my $num = @$pset;

    return 1 if (!defined $pset || @$pset == 0);

    foreach my $cnt (1..$num)
    {
        ($pset, $compat) = $self->_iterate($pset, $compat);
        return 1 if (!defined $pset || @$pset == 0);
    }
    printLog($self->request(), undef, LOG_DEBUG, "not a possible combi");
    return 0;
}

sub _iterate
{
    my $self = shift   || return ([], []);
    my $pset = shift   || return ([], []);
    my $compat = shift || return ($pset, []);
    my @notfound = ();

    my %pset_hash;
    map { $pset_hash{$_} = 1 } @$pset;

    foreach my $product (keys %pset_hash)
    {
        foreach my $c (@$compat)
        {
            if (SMT::Utils::isExtensionOf($self->dbh(), $product, $c, $self->request()) ||
                SMT::Utils::isExtensionOf($self->dbh(), $c, $product, $self->request())
            )
            {
                push @$compat, $product;
                $pset_hash{$product} = 0;
                last;
            }
        }
        if ($pset_hash{$product})
        {
            push @notfound, $product;
        }
    }
    return (\@notfound, $compat);
}

sub _deregister_product
{
    my $self = shift    || return 0;
    my $guid = shift    || return 0;
    my $regProd = shift || return 0;

    my $productId = SMT::Utils::lookupProductIdByName($self->dbh(),
                                                      $regProd->{'identifier'},
                                                      $regProd->{'version'},
                                                      $regProd->{'release_type'},
                                                      $regProd->{'arch'});

    my $statement = sprintf("DELETE FROM Registration WHERE GUID = %s AND PRODUCTID = %s",
                            $self->dbh()->quote($guid),
                            $self->dbh()->quote($productId));
    $self->request()->log->info("STATEMENT: $statement");
    eval
    {
        $self->dbh()->do($statement);
    };
    if ($@)
    {
        $self->request()->log->error("DBERROR: ".$self->dbh()->errstr);
        return 0;
    }
    #
    # delete product info into MachineData
    #
    $statement = sprintf("DELETE from MachineData where GUID=%s AND KEYNAME LIKE %s",
                         $self->dbh()->quote($guid),
                         $self->dbh()->quote("product-%-$productId"));
    $self->request()->log->info("STATEMENT: $statement");
    eval {
        $self->dbh()->do($statement);
    };
    if($@)
    {
        $self->request()->log->error("DBERROR: ".$self->dbh()->errstr);
        return 0;
    }
    return 1;
}
1;
