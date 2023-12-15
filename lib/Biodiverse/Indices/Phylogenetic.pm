#  Phylogenetic indices
#  A plugin for the biodiverse system and not to be used on its own.
package Biodiverse::Indices::Phylogenetic;
use 5.022;
use strict;
use warnings;

use English qw /-no_match_vars/;
use Carp;

use feature 'refaliasing';
no warnings 'experimental::refaliasing';

use Biodiverse::Progress;

use List::Util 1.33 qw /any sum min max/;
use Scalar::Util qw /blessed/;

our $VERSION = '4.99_001';

use constant HAVE_BD_UTILS => eval 'require Biodiverse::Utils';
use constant HAVE_BD_UTILS_108 => HAVE_BD_UTILS && eval '$Biodiverse::Utils::VERSION >= 1.08';

use constant HAVE_PANDA_LIB
  => !$ENV{BD_NO_USE_PANDA} && eval 'require Panda::Lib';

use constant HAVE_DATA_RECURSIVE
  => !$ENV{BD_NO_USE_PANDA} && eval 'require Data::Recursive';

  
#warn "Using Data::Recursive\n" if HAVE_DATA_RECURSIVE;

use parent qw /Biodiverse::Indices::Phylogenetic::RefAlias/;

use Biodiverse::Matrix::LowMem;
my $mx_class_for_trees = 'Biodiverse::Matrix::LowMem';

my $metadata_class = 'Biodiverse::Metadata::Indices';

sub get_metadata_calc_pd {

    my %metadata = (
        description     => 'Phylogenetic diversity (PD) based on branch '
                           . "lengths back to the root of the tree.\n"
                           . 'Uses labels in both neighbourhoods.',
        name            => 'Phylogenetic Diversity',
        type            => 'Phylogenetic Indices',
        pre_calc        => '_calc_pd',
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            PD              => {
                cluster       => undef,
                description   => 'Phylogenetic diversity',
                reference     => 'Faith (1992) Biol. Cons. https://doi.org/10.1016/0006-3207(92)91201-3',
                formula       => [
                    '= \sum_{c \in C} L_c',
                    ' where ',
                    'C',
                    'is the set of branches in the minimum spanning path '
                     . 'joining the labels in both neighbour sets to the root of the tree,',
                     'c',
                    ' is a branch (a single segment between two nodes) in the '
                    . 'spanning path ',
                    'C',
                    ', and ',
                    'L_c',
                    ' is the length of branch ',
                    'c',
                    '.',
                ],
                bounds      => [0, 'Inf'],
            },
            PD_P            => {
                cluster     => undef,
                description => 'Phylogenetic diversity as a proportion of total tree length',
                formula     => [
                    '= \frac { PD }{ \sum_{c \in C} L_c }',
                    ' where terms are the same as for PD, but ',
                    'c',
                    ', ',
                    'C',
                    ' and ',
                    'L_c',
                    ' are calculated for all nodes in the tree.',
                ],
                distribution => 'unit_interval',
                bounds       => [0, 1],
            },
            PD_per_taxon    => {
                cluster       => undef,
                description   => 'Phylogenetic diversity per taxon',
                formula       => [
                    '= \frac { PD }{ RICHNESS\_ALL }',
                ],
                bounds      => [0, 'Inf'],
            },
            PD_P_per_taxon  => {
                cluster       => undef,
                description   => 'Phylogenetic diversity per taxon as a proportion of total tree length',
                formula       => [
                    '= \frac { PD\_P }{ RICHNESS\_ALL }',
                ],
                distribution => 'unit_interval',
                bounds       => [0, 1],
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pd {
    my $self = shift;
    my %args = @_;
    
    my @keys = qw /PD PD_P PD_per_taxon PD_P_per_taxon/;
    my %results = %args{@keys};
    
    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pd_local {

    my %metadata = (
        description     => 'Phylogenetic diversity (PD) based on branch '
                           . "lengths back to the last shared ancestor.\n"
                           . 'Uses labels in both neighbourhoods.',
        name            => 'Phylogenetic Diversity (local)',
        type            => 'Phylogenetic Indices',
        required_args   => ['tree_ref'],
        pre_calc        => ['calc_pd', 'get_last_shared_ancestor_from_subtree'],
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            PD_LOCAL  => {
                description   => 'Phylogenetic diversity calculated to last shared ancestor',
                formula       => [
                    '= \sum_{c \in C} L_c',
                    ' where ',
                    'C',
                    'is the set of branches in the minimum spanning path '
                     . 'joining the labels in both neighbour sets to the last shared ancestor,',
                     'c',
                    ' is a branch (a single segment between two nodes) in the '
                    . 'spanning path ',
                    'C',
                    ', and ',
                    'L_c',
                    ' is the length of branch ',
                    'c',
                    '.',
                ],
            },
            PD_LOCAL_P => {
                description => 'Phylogenetic diversity as a proportion of total tree length',
                formula     => [
                    '= \frac { PD }{ \sum_{c \in C} L_c }',
                    ' where terms are the same as for PD, but ',
                    'c',
                    ', ',
                    'C',
                    ' and ',
                    'L_c',
                    ' are calculated for all nodes in the tree.',
                ],
                distribution => 'unit_interval',
                bounds       => [0, 1],
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pd_local {
    my ($self, %args) = @_;

    my $PD   = $args{PD};
    my $PD_P = $args{PD_P};
    my $ancestor_name = $args{LAST_SHARED_ANCESTOR_SUBTREE};

    #  single-terminal lineages go to the root
    #  so are just "normal" PD and PD_P
    if ($PD) {
        my $tree_ref = $args{tree_ref};
        my $ancestor = $tree_ref->get_node_ref_aa($ancestor_name);
        if (!$ancestor->is_terminal_node) {
            my $tree_ref = $args{tree_ref};
            my $sum      = 0;
            while ($ancestor) {
                $sum     += $ancestor->get_length;
                $ancestor = $ancestor->get_parent;
            }
            $PD   = $PD - $sum;  # this way we avoid low-bit rounding errors
            $PD_P = $PD ? ($PD / $tree_ref->get_total_tree_length) : 0;
        }
    }

    my $results = {
        PD_LOCAL   => $PD,
        PD_LOCAL_P => $PD_P,
    };

    return wantarray ? %$results : $results;
}

sub get_metadata_calc_last_shared_ancestor_props {

    my %metadata = (
        description     => "Properties of the last shared ancestor of an assemblage.\n"
                         . "Uses labels in both neighbourhoods.",
        name            => 'Last shared ancestor properties',
        type            => 'Phylogenetic Indices',
        required_args   => ['tree_ref'],
        pre_calc        => [
            'calc_abc', 'get_sub_tree_as_hash',
            'get_last_shared_ancestor_from_subtree',
        ],
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            LAST_SHARED_ANCESTOR_DEPTH  => {
                description => "Depth of last shared ancestor from the root.\n"
                             . "The root has a depth of zero.",
            },
            LAST_SHARED_ANCESTOR_LENGTH  => {
                description => 'Branch length of last shared ancestor',
            },
            LAST_SHARED_ANCESTOR_DIST_TO_ROOT  => {
                description => 'Distance along the tree from the last '
                             . "shared ancestor to the root.  \n"
                             . "Includes the shared ancestor's length.",
            },
            LAST_SHARED_ANCESTOR_DIST_TO_TIP  => {
                description => 'Distance along the tree from the last '
                             . "shared ancestor to the furthest tip in the sample.\n"
                             . "This is calculated from the point at which the "
                             . "lineages merge, which is the "
                             . "branch end further from the root",
            },
            LAST_SHARED_ANCESTOR_POS_REL  => {
                description => "Relative position of the last shared ancestor.\n"
                             . "Value is the fraction of the distance from the root to the furthest terminal."
                             . "This uses the point at which the lineages merge, and is the "
                             . "branch end further from the root",
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_last_shared_ancestor_props {
    my ($self, %args) = @_;

    my $tree_ref = $args{tree_ref};
    my $shared_ancestor_name
      = $args{LAST_SHARED_ANCESTOR_SUBTREE};
    my $ancestor = $tree_ref->get_node_ref_aa($shared_ancestor_name);

    if (!$ancestor) {
        my $results = {
            LAST_SHARED_ANCESTOR_POS_REL      => undef,
            LAST_SHARED_ANCESTOR_LENGTH       => undef,
            LAST_SHARED_ANCESTOR_DEPTH        => undef,
            LAST_SHARED_ANCESTOR_DIST_TO_TIP  => undef,
            LAST_SHARED_ANCESTOR_DIST_TO_ROOT => undef,
        };
        return wantarray ? %$results : $results;
    }

    my $node_hash = $args{SUBTREE_AS_HASH};
    
    my $depth  = $ancestor->get_depth;
    my $length = $ancestor->get_length;
    my $dist_to_tips = 0;
    
    if (!$ancestor->is_terminal_node) {
        #  Faster than getting the terminals,
        #  unless there are many labels not on the tree
        my $terminals = $args{label_hash_all};

        my $path_to_root_node
          = $ancestor->is_root_node
          ? {}
          : $ancestor->get_path_lengths_to_root_node_aa;
        my $path_len_to_root = sum (0, values %$path_to_root_node);

        foreach my $terminal_name (keys %$terminals) {
            next if !exists $node_hash->{$terminal_name};
            #  Use the main tree as its cache applies across runs.
            #  The subtree is transient to the current calculation set.
            my $path
              = $tree_ref->get_node_ref_aa($terminal_name)
                     ->get_path_lengths_to_root_node_aa;
            $dist_to_tips = max ($dist_to_tips, sum (0, values %$path));
        }
        $dist_to_tips -= $path_len_to_root;
    }

    my $dist_to_root = 0;
    if (!$ancestor->is_root_node) {
        while ($ancestor) {
            $dist_to_root += $ancestor->get_length;
            $ancestor = $ancestor->get_parent;
        }
    }
    my $rel_pos
      = ($dist_to_root || $dist_to_tips)
      ? $dist_to_root / ($dist_to_root + $dist_to_tips)
      : 0;

    my $results = {
        LAST_SHARED_ANCESTOR_POS_REL      => $rel_pos,
        LAST_SHARED_ANCESTOR_LENGTH       => $length,
        LAST_SHARED_ANCESTOR_DEPTH        => $depth,
        LAST_SHARED_ANCESTOR_DIST_TO_TIP  => $dist_to_tips,
        LAST_SHARED_ANCESTOR_DIST_TO_ROOT => $dist_to_root,
    };

    return wantarray ? %$results : $results;
}


sub get_metadata_calc_pd_node_list {

    my %metadata = (
        description     => 'Phylogenetic diversity (PD) nodes used.',
        name            => 'Phylogenetic Diversity node list',
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc        => '_calc_pd',
        uses_nbr_lists  => 1,  #  how many lists it must have
        #required_args   => {'tree_ref' => 1},
        indices         => {
            PD_INCLUDED_NODE_LIST => {
                description   => 'List of tree nodes included in the PD calculations',
                type          => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pd_node_list {
    my $self = shift;
    my %args = @_;
    
    my @keys = qw /PD_INCLUDED_NODE_LIST/;

    my %results = %args{@keys};

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pd_terminal_node_list {

    my %metadata = (
        description     => 'Phylogenetic diversity (PD) terminal nodes used.',
        name            => 'Phylogenetic Diversity terminal node list',
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc        => '_calc_pd',
        uses_nbr_lists  => 1,  #  how many lists it must have
        required_args   => {'tree_ref' => 1},
        indices         => {
            PD_INCLUDED_TERMINAL_NODE_LIST => {
                description   => 'List of tree terminal nodes included in the PD calculations',
                type          => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pd_terminal_node_list {
    my $self = shift;
    my %args = @_;

    my $tree_ref = $args{tree_ref};

    #  loop over nodes and just keep terminals
    my $pd_included_node_list = $args{PD_INCLUDED_NODE_LIST};
    #  this is awkward - we should be able to use Tree::get_terminal_elements directly,
    #  but it does odd things.
    my $root_node      = $tree_ref->get_root_node(tree_has_one_root_node => 1);
    my $tree_terminals = $root_node->get_terminal_elements;

    #  we could just use the ABC lists  
    my @terminal_keys = grep {exists $tree_terminals->{$_}} keys %$pd_included_node_list;
    my %terminals = %$pd_included_node_list{@terminal_keys};

    my %results = (
        PD_INCLUDED_TERMINAL_NODE_LIST => \%terminals,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pd_terminal_node_count {

    my %metadata = (
        description     => 'Number of terminal nodes in neighbour sets 1 and 2.',
        name            => 'Phylogenetic Diversity terminal node count',
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc        => 'calc_pd_terminal_node_list',
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            PD_INCLUDED_TERMINAL_NODE_COUNT => {
                description    => 'Count of tree terminal nodes included in the PD calculations',
                distribution => 'nonnegative',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pd_terminal_node_count {
    my $self = shift;
    my %args = @_;


    #  loop over nodes and just keep terminals
    my $node_list = $args{PD_INCLUDED_TERMINAL_NODE_LIST};
    
    my %results = (
        PD_INCLUDED_TERMINAL_NODE_COUNT => scalar keys %$node_list,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata__calc_pd {
    my %metadata = (
        description     => 'Phylogenetic diversity (PD) base calcs.',
        name            => 'Phylogenetic Diversity base calcs',
        type            => 'Phylogenetic Indices',
        pre_calc        => 'calc_labels_on_tree',
        pre_calc_global => [qw /get_path_length_cache set_path_length_cache_by_group_flag/],
        uses_nbr_lists  => 1,  #  how many lists it must have
        required_args   => {'tree_ref' => 1},
    );

    return $metadata_class->new(\%metadata);
}

#  calculate the phylogenetic diversity of the species in the central elements only
#  this function expects a tree reference as an argument.
sub _calc_pd {
    my $self = shift;
    my %args = @_;

    my $tree_ref   = $args{tree_ref};
    my $label_list = $args{PHYLO_LABELS_ON_TREE};
    my $richness   = scalar keys %$label_list;
    
    #  the el_list is used to trigger caching, and only if we have one element
    my $el_list = [];
    my $pass_el_list = scalar @{$args{element_list1} // []} + scalar @{$args{element_list2} // []};
    if ($pass_el_list == 1) {
        $el_list = [@{$args{element_list1} // []}, @{$args{element_list2} // []}];
    }

    my $nodes_in_path = $self->get_path_lengths_to_root_node (
        @_,
        labels  => $label_list,
        el_list => $el_list,
    );

    my $PD_score = sum values %$nodes_in_path;

    #  need to use node length instead of 1
    #my %included_nodes;
    #@included_nodes{keys %$nodes_in_path} = (1) x scalar keys %$nodes_in_path;
    #my %included_nodes = %$nodes_in_path;

    my ($PD_P, $PD_per_taxon, $PD_P_per_taxon);
    {
        no warnings 'uninitialized';
        if ($PD_score) {  # only if we have some PD
            $PD_P = $PD_score / $tree_ref->get_total_tree_length;
        }

        $PD_per_taxon   = eval {$PD_score / $richness};
        $PD_P_per_taxon = eval {$PD_P / $richness};
    }
    
    my %results = (
        PD                => $PD_score,
        PD_P              => $PD_P,
        PD_per_taxon      => $PD_per_taxon,
        PD_P_per_taxon    => $PD_P_per_taxon,

        PD_INCLUDED_NODE_LIST => $nodes_in_path,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_set_path_length_cache_by_group_flag {
    my $self = shift;

    my %metadata = (
        name            => 'Path length cache use flag',
        description     => 'Should we use the path length cache? It does not always need to be used.',
        uses_nbr_lists  => 1,  #  how many lists it must have
    );

    return $metadata_class->new(\%metadata);
    
}

sub set_path_length_cache_by_group_flag {
    my $self = shift;

    my $flag;

    #  do we have a combination of _calc_pe with _calc_pd or _calc_phylo_abc_lists, or are we in pairwise mode?
    if ($self->get_pairwise_mode) {
        $flag = 1;
    }
    else {
        no autovivification;
        my $validated_calcs = $self->get_param ('VALID_CALCULATIONS');
        my $dep_list       = $validated_calcs->{calc_deps_by_type}{pre_calc};
        if ($dep_list->{_calc_pe} && ($dep_list->{_calc_pd} || $dep_list->{_calc_phylo_abc_lists})) {
            $flag = 1;
        }
    }

    #  We set a param to avoid having to pass it around,
    #  as some of the subs which need it are not called as dependencies
    $self->set_param(USE_PATH_LENGTH_CACHE_BY_GROUP => $flag);
    
    #  no need to return any contents, but we do need to return something to keep the dep calc process happy
    return wantarray ? () : {};
}


sub get_metadata_get_path_length_cache {
    my $self = shift;

    my %metadata = (
        name            => 'get_path_length_cache',
        description     => 'Cache for path lengths.',
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            path_length_cache => {
                description => 'Path length cache hash',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_path_length_cache {
    my $self = shift;
    my %args = @_;

    my %results = (path_length_cache => {});

    return wantarray ? %results : \%results;
}

sub get_metadata_get_path_lengths_to_root_node {

    my %metadata = (
        name            => 'get_path_lengths_to_root_node',
        description     => 'Get the path lengths to the root node of a tree for a set of labels.',
        uses_nbr_lists  => 1,  #  how many lists it must have
        pre_calc_global => 'get_path_length_cache',
    );

    return $metadata_class->new(\%metadata);
}

#  get the paths to the root node of a tree for a set of labels
#  saves duplication of code in PD and PE subs
sub get_path_lengths_to_root_node {
    my $self = shift;
    my %args = (return_lengths => 1, @_);

    my $cache = !$args{no_cache};
    #$cache = 0;  #  turn it off for debug
    my $el_list = $args{el_list} // [];
    
    #  have we cached it?
    #my $use_path_cache = $cache && $self->get_pairwise_mode();
    my $use_path_cache
        =  $cache
        && $self->get_param('USE_PATH_LENGTH_CACHE_BY_GROUP')
        && scalar @$el_list == 1;  #  caching makes sense only if we have
                                   #  only one element (group) containing labels

    if ($use_path_cache) {
        my $cache_h   = $args{path_length_cache};
        #if (scalar @$el_list == 1) {  #  caching makes sense only if we have only one element (group) containing labels
            my $path = $cache_h->{$el_list->[0]};
            return (wantarray ? %$path : $path) if $path;
        #}
        #else {
        #    $use_path_cache = undef;  #  skip caching below
        #}
    }

    my $label_list = $args{labels};
    my $tree_ref   = $args{tree_ref}
      or croak "argument tree_ref is not defined\n";

    #  Avoid millions of subroutine calls below.
    #  We could use a global precalc, but that won't scale well with
    #  massive trees where we only need a subset.
    my $path_cache_master
      = $self->get_cached_value_dor_set_default_aa (PATH_LENGTH_CACHE_PER_TERMINAL => {});
    my $path_cache = $path_cache_master->{$tree_ref} //= {};

    # get a hash of node refs
    my $all_nodes = $tree_ref->get_node_hash;

    #  now loop through the labels and get the path to the root node
    my $path_hash = {};
    my @collected_paths;  #  used if we have B::Utils 1.07 or greater
    foreach my $label (grep exists $all_nodes->{$_}, keys %$label_list) {
        #  Could assign to $current_node here, but profiling indicates it
        #  takes meaningful chunks of time for large data sets
        my $current_node = $all_nodes->{$label};
        my $sub_path = $cache && $path_cache->{$current_node};

        if (!$sub_path) {
            $sub_path = $current_node->get_path_name_array_to_root_node_aa (!$cache);
            if ($cache) {
                $path_cache->{$current_node} = $sub_path;
            }
        }

        #  This is a bottleneck for large data sets,
        #  so use an XSUB if possible.
        if (HAVE_BD_UTILS_108) {
            #  collect them all and process in an xsub
            push @collected_paths, $sub_path;
        }
        elsif (HAVE_BD_UTILS) {
            Biodiverse::Utils::add_hash_keys_until_exists (
                $path_hash,
                $sub_path,
            );
        }
        else {
            #  The last-if approach is faster than a straight slice,
            #  but we should (might) be able to get even more speedup with XS code.  
            if (!scalar keys %$path_hash) {
                @$path_hash{@$sub_path} = ();
            }
            else {
                foreach my $node_name (@$sub_path) {
                    last if exists $path_hash->{$node_name};
                    $path_hash->{$node_name} = undef;
                }
            }
        }
    }

    #  Assign the lengths once each.
    #  ~15% faster than repeatedly assigning in the slice above
    #  but first option is faster still
    my $len_hash = $tree_ref->get_node_length_hash;
    if (HAVE_BD_UTILS_108) {
        #  get keys and vals in one call
        Biodiverse::Utils::XS::add_hash_keys_and_vals_until_exists_AoA (
            $path_hash, \@collected_paths, $len_hash,
        );
    }
    elsif (HAVE_BD_UTILS) {
        Biodiverse::Utils::copy_values_from ($path_hash, $len_hash);
    }
    else {
        @$path_hash{keys %$path_hash} = @$len_hash{keys %$path_hash};
    }

    if ($use_path_cache) {
        my $cache_h = $args{path_length_cache};
        #my @el_list = @$el_list;  #  can only have one item
        $cache_h->{$el_list->[0]} = $path_hash;
    }

    return wantarray ? %$path_hash : $path_hash;
}


sub get_metadata_calc_pe {

    my $formula = [
        'PE = \sum_{\lambda \in \Lambda } L_{\lambda}\frac{r_\lambda}{R_\lambda}',
        ' where ',
        '\Lambda', ' is the set of branches found across neighbour sets 1 and 2, ',
        'L_\lambda', ' is the length of branch ',       '\lambda', ', ',
        'r_\lambda', ' is the local range of branch ',  '\lambda',
            '(the number of groups in neighbour sets 1 and 2 containing it), and ',
        'R_\lambda', ' is the global range of branch ', '\lambda',
            ' (the number of groups across the entire data set containing it).',
    ];
    
    my %metadata = (
        description     => 'Phylogenetic endemism (PE). '
                            . 'Uses labels across both neighbourhoods and '
                            . 'trims the tree to exclude labels not in the '
                            . 'BaseData object.',
        name            => 'Phylogenetic Endemism',
        reference       => 'Rosauer et al (2009) Mol. Ecol. https://doi.org/10.1111/j.1365-294X.2009.04311.x'
                         . '; Laity et al. (2015) https://doi.org/10.1016/j.scitotenv.2015.04.113'
                         . '; Laffan et al. (2016) https://doi.org/10.1111/2041-210X.12513',
        type            => 'Phylogenetic Endemism Indices',
        pre_calc        => ['_calc_pe'],  
        uses_nbr_lists  => 1,  #  how many lists it must have
        formula         => $formula,
        indices         => {
            PE_WE           => {
                description => 'Phylogenetic endemism'
            },
            PE_WE_P         => {
                description => 'Phylogenetic weighted endemism as a proportion of the total tree length',
                formula     => [ 'PE\_WE / L', ' where L is the sum of all branch lengths in the trimmed tree' ],
                distribution => 'unit_interval',
                bounds       => [0, 1],
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pe {
    my $self = shift;
    my %args = @_;
    
    my @keys = qw /PE_WE PE_WE_P/;
    my %results = %args{@keys};
    
    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pe_lists {

    my %metadata = (
        description     => 'Lists used in the Phylogenetic endemism (PE) calculations.',
        name            => 'Phylogenetic Endemism lists',
        reference       => 'Rosauer et al (2009) Mol. Ecol. https://doi.org/10.1111/j.1365-294X.2009.04311.x',
        type            => 'Phylogenetic Endemism Indices', 
        pre_calc        => ['_calc_pe'],  
        uses_nbr_lists  => 1,
        distribution => 'nonnegative',
        indices         => {
            PE_WTLIST       => {
                description => 'Node weights used in PE calculations',
                type        => 'list',
            },
            PE_RANGELIST    => {
                description => 'Node ranges used in PE calculations',
                type        => 'list',
            },
            PE_LOCAL_RANGELIST => {
                description => 'Local node ranges used in PE calculations (number of groups in which a node is found)',
                type        => 'list',
            }
        },
    );
    
    return $metadata_class->new(\%metadata);
}

sub calc_pe_lists {
    my $self = shift;
    my %args = @_;

    my @keys = qw /PE_WTLIST PE_RANGELIST PE_LOCAL_RANGELIST/;
    my %results = %args{@keys};

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pe_central {

    my $desc = <<'END_PEC_DESC'
A variant of Phylogenetic endemism (PE) that uses labels
from neighbour set 1 but local ranges from across
both neighbour sets 1 and 2.  Identical to PE if only
one neighbour set is specified.
END_PEC_DESC
  ;

    my $formula = [
        'PEC = \sum_{\lambda \in \Lambda } L_{\lambda}\frac{r_\lambda}{R_\lambda}',
        ' where ',
        '\Lambda', ' is the set of branches found across neighbour set 1 only, ',
        'L_\lambda', ' is the length of branch ',       '\lambda', ', ',
        'r_\lambda', ' is the local range of branch ',  '\lambda',
            '(the number of groups in neighbour sets 1 and 2 containing it), and ',
        'R_\lambda', ' is the global range of branch ', '\lambda',
            ' (the number of groups across the entire data set containing it).',
    ];
    
    my %metadata = (
        description     => $desc,
        name            => 'Phylogenetic Endemism central',
        reference       => 'Rosauer et al (2009) Mol. Ecol. https://doi.org/10.1111/j.1365-294X.2009.04311.x',
        type            => 'Phylogenetic Endemism Indices',
        pre_calc        => [qw /_calc_pe _calc_phylo_abc_lists/],
        pre_calc_global => [qw /get_trimmed_tree/],
        uses_nbr_lists  => 1,  #  how many lists it must have
        formula         => $formula,
        indices         => {
            PEC_WE           => {
                description => 'Phylogenetic endemism, central variant'
            },
            PEC_WE_P         => {
                description => 'Phylogenetic weighted endemism as a proportion of the total tree length, central variant',
                distribution => 'unit_interval',
                bounds       => [0, 1],
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pe_central {
    my $self = shift;
    my %args = @_;

    my $tree_ref    = $args{trimmed_tree};

    my $pe      = $args{PE_WE};
    my $pe_p    = $args{PE_WE_P};
    my $wt_list = $args{PE_WTLIST};
    my $c_list  = $args{PHYLO_C_LIST};  #  those only in nbr set 2

    #  remove the PE component found only in nbr set 2
    #  (assuming c_list is shorter than a+b, so this will be the faster approach)
    $pe -= sum (0, @$wt_list{keys %$c_list});

    $pe_p = $pe ? $pe / $tree_ref->get_total_tree_length : undef;

    my %results = (
        PEC_WE     => $pe,
        PEC_WE_P   => $pe_p,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pe_central_lists {

    my $desc = <<'END_PEC_DESC'
Lists underlying the phylogenetic endemism central indices.
Uses labels from neighbour set one but local ranges from across
both neighbour sets.
END_PEC_DESC
  ;

    my %metadata = (
        description     => $desc,
        name            => 'Phylogenetic Endemism central lists',
        reference       => 'Rosauer et al (2009) Mol. Ecol. https://doi.org/10.1111/j.1365-294X.2009.04311.x',
        type            => 'Phylogenetic Endemism Indices',
        pre_calc        => [qw /_calc_pe _calc_phylo_abc_lists/],
        uses_nbr_lists  => 1,  #  how many lists it must have
        distribution => 'nonnegative',
        indices         => {
            PEC_WTLIST           => {
                description => 'Phylogenetic endemism weights, central variant',
                type => 'list',
            },
            PEC_LOCAL_RANGELIST  => {
                description => 'Phylogenetic endemism local range lists, central variant',
                type => 'list',
            },
            PEC_RANGELIST => {
                description => 'Phylogenetic endemism global range lists, central variant',
                type => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pe_central_lists {
    my $self = shift;
    my %args = @_;

    my $base_wt_list = $args{PE_WTLIST};
    my $c_list  =   $args{PHYLO_C_LIST};  #  those only in nbr set 2
    my $a_list  =   $args{PHYLO_A_LIST};  #  those in both lists
    my $b_list  =   $args{PHYLO_B_LIST};  #  those only in nbr set 1

    my $local_range_list  = $args{PE_LOCAL_RANGELIST};
    my $global_range_list = $args{PE_RANGELIST};

    my %results;

    #  avoid copies and slices if there are no nodes found only in nbr set 2
    if (scalar keys %$c_list) {
        #  Keep any node found in nbr set 1
        my %wt_list = %{$base_wt_list}{(keys %$a_list, keys %$b_list)};
        my %local_range_list_c  = %{$local_range_list}{keys %wt_list};
        my %global_range_list_c = %{$global_range_list}{keys %wt_list};

        $results{PEC_WTLIST} = \%wt_list;
        $results{PEC_LOCAL_RANGELIST} = \%local_range_list_c;
        $results{PEC_RANGELIST}       = \%global_range_list_c;
    }
    else {
        $results{PEC_WTLIST} = $base_wt_list;
        $results{PEC_LOCAL_RANGELIST} = $local_range_list;
        $results{PEC_RANGELIST}       = $global_range_list;
    }


    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pe_central_cwe {

    my %metadata = (
        name            => 'Corrected weighted phylogenetic endemism, central variant',
        description     => 'What proportion of the PD in neighbour set 1 is '
                         . 'range-restricted to neighbour sets 1 and 2?',
        reference       => '',
        type            => 'Phylogenetic Endemism Indices', 
        pre_calc        => [qw /calc_pe_central calc_pe_central_lists calc_pd_node_list/],
        uses_nbr_lists  => 1,
        indices         => {
            PEC_CWE => {
                description => 'Corrected weighted phylogenetic endemism, central variant',
                distribution => 'unit_interval',
                bounds       => [0, 1],
            },
            PEC_CWE_PD => {
                description => 'PD used in the PEC_CWE index.',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pe_central_cwe {
    my $self = shift;
    my %args = @_;

    my $pe      = $args{PEC_WE};
    my $wt_list = $args{PEC_WTLIST};

    my $pd_included_node_list = $args{PD_INCLUDED_NODE_LIST};

    my $pd = sum @$pd_included_node_list{keys %$wt_list};

    my $cwe = $pd ? $pe / $pd : undef;

    my %results = (
        PEC_CWE    => $cwe,
        PEC_CWE_PD => $pd,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pd_clade_contributions {

    my %metadata = (
        description     => 'Contribution of each node and its descendents to the Phylogenetic diversity (PD) calculation.',
        name            => 'PD clade contributions',
        reference       => '',
        type            => 'Phylogenetic Indices', 
        pre_calc        => [qw /calc_pd calc_pd_node_list get_sub_tree_as_hash/],
        #pre_calc_global => ['get_trimmed_tree'],
        uses_nbr_lists  => 1,
        indices         => {
            PD_CLADE_SCORE  => {
                description => 'List of PD scores for each node (clade), being the sum of all descendent branch lengths',
                type        => 'list',
            },
            PD_CLADE_CONTR  => {
                description => 'List of node (clade) contributions to the PD calculation',
                type        => 'list',
            },
            PD_CLADE_CONTR_P => {
                description => 'List of node (clade) contributions to the PD calculation, proportional to the entire tree',
                type        => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pd_clade_contributions {
    my $self = shift;
    my %args = @_;
    
    return $self->_calc_pd_pe_clade_contributions(
        %args,
        node_list => $args{PD_INCLUDED_NODE_LIST},
        p_score   => $args{PD},
        res_pfx   => 'PD_',
    );
}


sub _calc_pd_pe_clade_contributions {
    my $self = shift;
    my %args = @_;

    my $main_tree = $args{tree_ref};
    my $wt_list   = $args{node_list};
    my $p_score   = $args{p_score};
    my $res_pfx   = $args{res_pfx};
    my $sum_of_branches = $main_tree->get_total_tree_length;

    my %contr;
    my %contr_p;
    my %clade_score;

    #  depths are (should be) the same across main and sub trees
    \my %depth_hash = $main_tree->get_node_name_depth_hash;
    \my %node_hash  = $args{SUBTREE_AS_HASH};

    my @names_by_depth;
    foreach my $node_name (keys %node_hash) {
        my $aref = $names_by_depth[$depth_hash{$node_name}] //= [];
        push @$aref, $node_name;
    }

  DEPTH:
    foreach my $name_arr (reverse @names_by_depth) {

      NODE_NAME:
        foreach my $node_name (@$name_arr) {

            my $wt_sum = $wt_list->{$node_name};
            #  postfix for speed
            $wt_sum += $clade_score{$_}
              for @{$node_hash{$node_name}};
    
            #  Round off to avoid spurious spatial variation.
            #  times-int-divide is faster than sprintf
            $contr{$node_name}
              = $p_score
              ? int (1e11 * $wt_sum / $p_score) / 1e11
              : undef;
            $contr_p{$node_name}
              = $sum_of_branches
              ? int (1e11 * $wt_sum / $sum_of_branches) / 1e11
              : undef;
            $clade_score{$node_name} = $wt_sum;
        }
    }

    my %results = (
        "${res_pfx}CLADE_SCORE"   => \%clade_score,
        "${res_pfx}CLADE_CONTR"   => \%contr,
        "${res_pfx}CLADE_CONTR_P" => \%contr_p,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pe_clade_contributions {

    my %metadata = (
        description     => 'Contribution of each node and its descendents to the Phylogenetic endemism (PE) calculation.',
        name            => 'PE clade contributions',
        reference       => '',
        type            => 'Phylogenetic Endemism Indices', 
        pre_calc        => ['_calc_pe', 'get_sub_tree_as_hash'],
        pre_calc_global => ['get_trimmed_tree'],
        uses_nbr_lists  => 1,
        indices         => {
            PE_CLADE_SCORE  => {
                description => 'List of PE scores for each node (clade), being the sum of all descendent PE weights',
                type        => 'list',
            },
            PE_CLADE_CONTR  => {
                description => 'List of node (clade) contributions to the PE calculation',
                type        => 'list',
            },
            PE_CLADE_CONTR_P => {
                description => 'List of node (clade) contributions to the PE calculation, proportional to the entire tree',
                type        => 'list',
                distribution => 'unit_interval',
                bounds       => [0, 1],
            },
        },
    );
    
    return $metadata_class->new(\%metadata);
}

sub calc_pe_clade_contributions {
    my $self = shift;
    my %args = @_;
    
    return $self->_calc_pd_pe_clade_contributions(
        %args,
        node_list => $args{PE_WTLIST},
        p_score   => $args{PE_WE},
        res_pfx   => 'PE_',
        tree_ref  => $args{trimmed_tree},
    );
}


sub get_metadata_calc_pd_clade_loss {

    my %metadata = (
        description     => 'How much of the PD would be lost if a clade were to be removed? '
                         . 'Calculates the clade PD below the last ancestral node in the '
                         . 'neighbour set which would still be in the neighbour set.',
        name            => 'PD clade loss',
        reference       => '',
        type            => 'Phylogenetic Indices', 
        pre_calc        => [qw /calc_pd_clade_contributions get_sub_tree_as_hash/],
        #pre_calc_global => ['get_trimmed_tree'],
        uses_nbr_lists  => 1,
        indices         => {
            PD_CLADE_LOSS_SCORE  => {
                description => 'List of how much PD would be lost if each clade were removed.',
                type        => 'list',
            },
            PD_CLADE_LOSS_CONTR  => {
                description => 'List of the proportion of the PD score which would be lost '
                             . 'if each clade were removed.',
                type        => 'list',
            },
            PD_CLADE_LOSS_CONTR_P => {
                description => 'As per PD_CLADE_LOSS but proportional to the entire tree',
                type        => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pd_clade_loss {
    my $self = shift;
    my %args = @_;
    
    return $self->_calc_pd_pe_clade_loss (
        %args,
        res_pfx => 'PD_',
    );
}

sub get_metadata_calc_pe_clade_loss {

    my %metadata = (
        description     => 'How much of the PE would be lost if a clade were to be removed? '
                         . 'Calculates the clade PE below the last ancestral node in the '
                         . 'neighbour set which would still be in the neighbour set.',
        name            => 'PE clade loss',
        reference       => '',
        type            => 'Phylogenetic Endemism Indices', 
        pre_calc        => [qw /calc_pe_clade_contributions get_sub_tree_as_hash/],
        #pre_calc_global => ['get_trimmed_tree'],
        uses_nbr_lists  => 1,
        indices         => {
            PE_CLADE_LOSS_SCORE  => {
                description => 'List of how much PE would be lost if each clade were removed.',
                type        => 'list',
            },
            PE_CLADE_LOSS_CONTR  => {
                description => 'List of the proportion of the PE score which would be lost '
                             . 'if each clade were removed.',
                type        => 'list',
            },
            PE_CLADE_LOSS_CONTR_P => {
                description => 'As per PE_CLADE_LOSS but proportional to the entire tree',
                type        => 'list',
                distribution => 'unit_interval',
                bounds       => [0, 1],
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pe_clade_loss {
    my $self = shift;
    my %args = @_;
    
    return $self->_calc_pd_pe_clade_loss (
        %args,
        res_pfx => 'PE_',
    );
}


sub _calc_pd_pe_clade_loss {
    my $self = shift;
    my %args = @_;

    my $tree_ref = $args{trimmed_tree} // $args{tree_ref};
    \my %sub_tree_hash = $args{SUBTREE_AS_HASH};

    my $pfx = $args{res_pfx};
    my @score_names = map {$pfx . $_} qw /CLADE_SCORE CLADE_CONTR CLADE_CONTR_P/;

    my ($p_clade_score, $p_clade_contr, $p_clade_contr_p)
      = @args{@score_names};

    my (%loss_contr, %loss_contr_p, %loss_score);
    
    \my %parent_hash = $tree_ref->get_node_name_parent_hash;

  NODE:
    foreach my $node_name (keys %sub_tree_hash) {

        #  skip if we have already done this one
        next NODE if defined $loss_score{$node_name};

        my @ancestors = ($node_name);

        #  Find the ancestors with no children outside this clade
        #  We are using a subtree, so the node only needs one sibling
        my $parent_name = $parent_hash{$node_name};
      PARENT:
        while (defined $parent_name) {
            last PARENT
              if @{$sub_tree_hash{$parent_name}} > 1;

            push @ancestors, $parent_name;
            $parent_name = $parent_hash{$parent_name};
        }

        my $last_ancestor = $ancestors[-1];

        foreach my $node_name (@ancestors) {
            #  these all have the same loss
            $loss_contr{$node_name}   = $p_clade_contr->{$last_ancestor};
            $loss_score{$node_name}   = $p_clade_score->{$last_ancestor};
            $loss_contr_p{$node_name} = $p_clade_contr_p->{$last_ancestor};
        }
    }

    my %results = (
        "${pfx}CLADE_LOSS_SCORE"   => \%loss_score,
        "${pfx}CLADE_LOSS_CONTR"   => \%loss_contr,
        "${pfx}CLADE_LOSS_CONTR_P" => \%loss_contr_p,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_pd_clade_loss_ancestral {

    my %metadata = (
        description     => 'How much of the PD clade loss is due to the ancestral branches? '
                         . 'The score is zero when there is no ancestral loss.',
        name            => 'PD clade loss (ancestral component)',
        reference       => '',
        type            => 'Phylogenetic Indices', 
        pre_calc        => [qw /calc_pd_clade_contributions calc_pd_clade_loss/],
        uses_nbr_lists  => 1,
        indices         => {
            PD_CLADE_LOSS_ANC => {
                description => 'List of how much ancestral PE would be lost '
                             . 'if each clade were removed.  '
                             . 'The value is 0 when no ancestral PD is lost.',
                type        => 'list',
            },
            PD_CLADE_LOSS_ANC_P  => {
                description => 'List of the proportion of the clade\'s PD loss '
                    . 'that is due to the ancestral branches.',
                type        => 'list',
                distribution => 'unit_interval',
                bounds       => [0, 1],
            },
        },
    );

    return $metadata_class->new(\%metadata);
}


sub calc_pd_clade_loss_ancestral {
    my $self = shift;
    my %args = @_;
    
    return $self->_calc_pd_pe_clade_loss_ancestral (
        %args,
        res_pfx => 'PD_',
    );
}


sub get_metadata_calc_pe_clade_loss_ancestral {

    my %metadata = (
        description     => 'How much of the PE clade loss is due to the ancestral branches? '
                         . 'The score is zero when there is no ancestral loss.',
        name            => 'PE clade loss (ancestral component)',
        reference       => '',
        type            => 'Phylogenetic Endemism Indices', 
        pre_calc        => [qw /calc_pe_clade_contributions calc_pe_clade_loss/],
        uses_nbr_lists  => 1,
        indices         => {
            PE_CLADE_LOSS_ANC => {
                description => 'List of how much ancestral PE would be lost '
                             . 'if each clade were removed.  '
                             . 'The value is 0 when no ancestral PE is lost.',
                type        => 'list',
            },
            PE_CLADE_LOSS_ANC_P  => {
                description => 'List of the proportion of the clade\'s PE loss '
                    . 'that is due to the ancestral branches.',
                type        => 'list',
                distribution => 'unit_interval',
                bounds       => [0, 1],
            },
        },
    );

    return $metadata_class->new(\%metadata);
}


sub calc_pe_clade_loss_ancestral {
    my $self = shift;
    my %args = @_;
    
    return $self->_calc_pd_pe_clade_loss_ancestral (
        %args,
        res_pfx => 'PE_',
    );
}

sub _calc_pd_pe_clade_loss_ancestral {
    my $self = shift;
    my %args = @_;

    my $pfx = $args{res_pfx};
    my @score_names = map {$pfx . $_} qw /CLADE_SCORE CLADE_LOSS_SCORE/;

    my ($p_clade_score, $p_clade_loss) =
      @args{@score_names};

    my (%loss_ancestral, %loss_ancestral_p);

    while (my ($node_name, $score) = each %$p_clade_score) {
        my $score = $p_clade_loss->{$node_name}
                  - $p_clade_score->{$node_name};
        $loss_ancestral{$node_name}   = $score;
        my $loss = $p_clade_loss->{$node_name};
        $loss_ancestral_p{$node_name} = $loss ? $score / $loss : 0;
    }

    my %results = (
        "${pfx}CLADE_LOSS_ANC"   => \%loss_ancestral,
        "${pfx}CLADE_LOSS_ANC_P" => \%loss_ancestral_p,
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_pe_single {

    my $formula = [
        'PE\_SINGLE = \sum_{\lambda \in \Lambda } L_{\lambda}\frac{1}{R_\lambda}',
        ' where ',
        '\Lambda', ' is the set of branches found across neighbour sets 1 and 2, ',
        'L_\lambda', ' is the length of branch ',       '\lambda', ', ',
        'R_\lambda', ' is the global range of branch ', '\lambda',
            ' (the number of groups across the entire data set containing it).',
    ];
    
    my $description = <<'EOD'
PE scores, but not weighted by local ranges.
This is the strict interpretation of the formula given in
Rosauer et al. (2009), although the approach has always been
implemented as the fraction of each branch's geographic range
that is found in the sample window (see formula for PE_WE).
EOD
  ;

    my %metadata = (
        description     => $description,
        name            => 'Phylogenetic Endemism single',
        reference       => 'Rosauer et al (2009) Mol. Ecol. https://doi.org/10.1111/j.1365-294X.2009.04311.x',
        type            => 'Phylogenetic Endemism Indices',
        pre_calc        => ['_calc_pe'],
        pre_calc_global => ['get_trimmed_tree'],
        uses_nbr_lists  => 1,
        indices         => {
            PE_WE_SINGLE    => {
                description => "Phylogenetic endemism unweighted by the number of neighbours.\n"
                               . "Counts each label only once, regardless of how many groups in the neighbourhood it is found in.\n"
                               . 'Useful if your data have sampling biases. '
                               . 'Better with small sample windows.'
            },
            PE_WE_SINGLE_P  => {
                description => "Phylogenetic endemism unweighted by the number of neighbours as a proportion of the total tree length.\n"
                    . "Counts each label only once, regardless of how many groups in the neighbourhood it is found.\n"
                    . "Useful if your data have sampling biases.",
                distribution => 'unit_interval',
                bounds       => [0, 1],
            },
        },
    );
    
    return $metadata_class->new(\%metadata);
}

sub calc_pe_single {
    my $self = shift;
    my %args = @_;
    
    my $node_ranges = $args{PE_RANGELIST};
    #my %wts;
    my $tree = $args{trimmed_tree};
    my $pe_single;

    foreach my $node_name (keys %$node_ranges) {
        my $range    = $node_ranges->{$node_name};
        my $node_ref = $tree->get_node_ref_aa ($node_name);
        #$wts{$node_name} = $node_ref->get_length;
        $pe_single += $node_ref->get_length / $range;
    }
    
    my $tree_length = $tree->get_total_tree_length;
    my $pe_single_p = defined $pe_single ? ($pe_single / $tree_length) : undef;
    
    my %results = (
        PE_WE_SINGLE   => $pe_single,
        PE_WE_SINGLE_P => $pe_single_p,
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_pd_endemism {

    my %metadata = (
        description     => 'Absolute endemism analogue of PE.  '
                        .  'It is the sum of the branch lengths restricted '
                        .  'to the neighbour sets.',
        name            => 'PD-Endemism',
        reference       => 'See Faith (2004) Cons Biol.  https://doi.org/10.1111/j.1523-1739.2004.00330.x',
        type            => 'Phylogenetic Endemism Indices',
        pre_calc        => ['calc_pe_lists'],
        pre_calc_global => [qw /get_trimmed_tree/],
        uses_nbr_lists  => 1,  #  how many lists it must have
        indices         => {
            PD_ENDEMISM => {
                description => 'Phylogenetic Diversity Endemism',
            },
            PD_ENDEMISM_WTS => {
                description => 'Phylogenetic Diversity Endemism weights per node found only in the neighbour set',
                type        => 'list',
            },
            PD_ENDEMISM_P => {
                description => 'Phylogenetic Diversity Endemism, as a proportion of the whole tree',
                distribution => 'unit_interval',
                bounds       => [0, 1],
            },
            #PD_ENDEMISM_R => {  #  should put in its own calc as it needs an extra dependency
            #    description => 'Phylogenetic Diversity Endemism, as a proportion of the local PD',
            #},
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_pd_endemism {
    my $self = shift;
    my %args = @_;

    my $weights   = $args{PE_WTLIST};
    my $tree_ref  = $args{trimmed_tree};
    my $total_len = $tree_ref->get_total_tree_length;
    my $global_range_hash = $args{PE_RANGELIST};
    my $local_range_hash  = $args{PE_LOCAL_RANGELIST};

    my $pd_e;
    my %pd_e_wts;

  LABEL:
    foreach my $label (keys %$weights) {
        next LABEL if $global_range_hash->{$label} != $local_range_hash->{$label};

        my $wt = $weights->{$label};
        $pd_e += $wt;
        $pd_e_wts{$label} = $wt;
    }

    my $pd_e_p = (defined $pd_e && $total_len) ? ($pd_e / $total_len) : undef;

    my %results = (
        PD_ENDEMISM     => $pd_e,
        PD_ENDEMISM_P   => $pd_e_p,
        PD_ENDEMISM_WTS => \%pd_e_wts,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata__calc_pe {

    my %metadata = (
        description     => 'Phylogenetic endemism (PE) base calcs.',
        name            => 'Phylogenetic Endemism base calcs',
        reference       => 'Rosauer et al (2009) Mol. Ecol. https://doi.org/10.1111/j.1365-294X.2009.04311.x',
        type            => 'Phylogenetic Endemism Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc_global => [ qw /
            get_node_range_hash
            get_trimmed_tree
            get_pe_element_cache
            get_path_length_cache
            set_path_length_cache_by_group_flag
            get_inverse_range_weighted_path_lengths
        /],
        pre_calc        => ['calc_abc'],  #  don't need calc_abc2 as we don't use its counts
        uses_nbr_lists  => 1,  #  how many lists it must have
        required_args   => {'tree_ref' => 1},
    );
    
    return $metadata_class->new(\%metadata);
}


sub get_metadata_calc_count_labels_on_tree {
    my $self = shift;

    my %metadata = (
        description     => 'Count the number of labels that are on the tree',
        name            => 'Count labels on tree',
        indices         => {
            PHYLO_LABELS_ON_TREE_COUNT => {
                description => 'The number of labels that are found on the tree, across both neighbour sets',
                distribution => 'nonnegative',
            },
        },
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc        => ['calc_labels_on_tree'],
        uses_nbr_lists  => 1,  #  how many lists it must have
    );

    return $metadata_class->new(\%metadata);
}

sub calc_count_labels_on_tree {
    my $self = shift;
    my %args = @_;
    
    my $labels_on_tree = $args{PHYLO_LABELS_ON_TREE};
    
    my %results = (PHYLO_LABELS_ON_TREE_COUNT => scalar keys %$labels_on_tree);

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_labels_on_tree {
    my $self = shift;

    my %metadata = (
        description     => 'Create a hash of the labels that are on the tree',
        name            => 'Labels on tree',
        indices         => {
            PHYLO_LABELS_ON_TREE => {
                description => 'A hash of labels that are found on the tree, across both neighbour sets',
                type        => 'list',
            },  #  should poss also do nbr sets 1 and 2
        },
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc_global => [qw /get_labels_not_on_tree/],
        pre_calc        => ['calc_abc'],
        uses_nbr_lists  => 1,  #  how many lists it must have
        required_args   => ['tree_ref'],
    );

    return $metadata_class->new(\%metadata);
}

sub calc_labels_on_tree {
    my $self = shift;
    my %args = @_;
    
    my %labels = %{$args{label_hash_all}};
    my $not_on_tree = $args{labels_not_on_tree};
    delete @labels{keys %$not_on_tree};
    
    my %results = (PHYLO_LABELS_ON_TREE => \%labels);
    
    return wantarray ? %results : \%results;
}

sub get_metadata_calc_labels_not_on_tree {
    my $self = shift;

    my %metadata = (
        description     => 'Create a hash of the labels that are not on the tree',
        name            => 'Labels not on tree',
        indices         => {
            PHYLO_LABELS_NOT_ON_TREE => {
                description => 'A hash of labels that are not found on the tree, across both neighbour sets',
                type        => 'list',
            },  #  should poss also do nbr sets 1 and 2
            PHYLO_LABELS_NOT_ON_TREE_N => {
                description => 'Number of labels not on the tree',
                distribution => 'nonnegative',
            },
            PHYLO_LABELS_NOT_ON_TREE_P => {
                description => 'Proportion of labels not on the tree',
                distribution => 'unit_interval',
                bounds       => [0, 1],
            },
        },
        type            => 'Phylogenetic Indices',  #  keeps it clear of the other indices in the GUI
        pre_calc_global => [qw /get_labels_not_on_tree/],
        pre_calc        => ['calc_abc'],
        uses_nbr_lists  => 1,  #  how many lists it must have
        required_args   => ['tree_ref'],
    );

    return $metadata_class->new(\%metadata);
}

sub calc_labels_not_on_tree {
    my $self = shift;
    my %args = @_;

    my $not_on_tree = $args{labels_not_on_tree};

    my %labels1 = %{$args{label_hash_all}};
    my $richness = scalar keys %labels1;
    delete @labels1{keys %$not_on_tree};

    my %labels2 = %{$args{label_hash_all}};
    delete @labels2{keys %labels1};

    my $count_not_on_tree = scalar keys %labels2;
    my $p_not_on_tree;
    {
        no warnings 'numeric';
        $p_not_on_tree = eval { $count_not_on_tree / $richness } || 0;
    }

    my %results = (
        PHYLO_LABELS_NOT_ON_TREE   => \%labels2,
        PHYLO_LABELS_NOT_ON_TREE_N => $count_not_on_tree,
        PHYLO_LABELS_NOT_ON_TREE_P => $p_not_on_tree,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_get_pe_element_cache {
    
    my %metadata = (
        name        => 'get_pe_element_cache',
        description => 'Create a hash in which to cache the PE scores for each element',
        indices     => {
            PE_RESULTS_CACHE => {
                description => 'The hash in which to cache the PE scores for each element'
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

#  create a hash in which to cache the PE scores for each element
#  this is called as a global precalc and then used or modified by each element as needed
sub get_pe_element_cache {
    my $self = shift;
    my %args = @_;

    my %results = (PE_RESULTS_CACHE => {});
    return wantarray ? %results : \%results;
}


#  get the node ranges as lists
sub get_metadata_get_node_range_hash_as_lists {
    my %metadata = (
        name            => 'get_node_range_hash_as_lists',
        description     => 'Get a hash of the node range lists across the basedata',
        pre_calc_global => ['get_trimmed_tree'],
        indices => {
            node_range_hash => {
                description => 'Hash of node range lists',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_node_range_hash_as_lists {
    my $self = shift;
    my %args = @_;

    my $res = $self->get_node_range_hash (@_, return_lists => 1);
    my %results = (
        node_range_hash => $res->{node_range},
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_get_inverse_range_weighted_path_lengths {
    my %metadata = (
        name  => 'get_metadata_get_node_range_hash',
        description
            => "Get a hash of the node lengths divided by their ranges\n"
             . "Forms the basis of the PE calcs for equal area cells",
        required_args => ['tree_ref'],
        pre_calc_global => ['get_node_range_hash'],
        indices => {
            inverse_range_weighted_node_lengths => {
                description => 'Hash of node lengths divided by their ranges',
            },
        },
    );
    return $metadata_class->new(\%metadata);
}

sub get_inverse_range_weighted_path_lengths {
    my $self = shift;
    my %args = @_;
    
    my $tree = $args{tree_ref};
    my $node_ranges = $args{node_range};
    
    my %range_weighted;
    
    foreach my $node ($tree->get_node_refs) {
        my $name = $node->get_name;
        next if !$node_ranges->{$name};
        $range_weighted{$name} = $node->get_length / $node_ranges->{$name};
    }
    
    my %results = (inverse_range_weighted_node_lengths => \%range_weighted);
    
    return wantarray ? %results : \%results;
}


sub get_metadata_get_node_range_hash {
    my %metadata = (
        name            => 'get_node_range_hash',
        description     => 'Get a hash of the node ranges across the basedata',
        pre_calc_global => ['get_trimmed_tree'],
        indices => {
            node_range => {
                description => 'Hash of node ranges',
            },
        },
    );
    return $metadata_class->new(\%metadata);
}

#  needs a cleanup - see get_global_node_abundance_hash
# calculate the range occupied by each node/clade in a tree
# this function expects a tree reference as an argument
sub get_node_range_hash { 
    my $self = shift;
    my %args = @_;

    my $return_lists = $args{return_lists};

    my $progress_bar = Biodiverse::Progress->new();    

    say "[PD INDICES] Calculating range for each node in the tree";

    my $tree  = $args{trimmed_tree} || croak "Argument trimmed_tree missing\n";  
    my $nodes = $tree->get_node_hash;
    my %node_range;

    my $to_do = scalar keys %$nodes;
    my $count = 0;
    print "[PD INDICES] Progress (% of $to_do nodes): ";

    my $progress      = $count / $to_do;
    my $progress_text = int (100 * $progress);
    $progress_bar->update(
        "Calculating node ranges\n($progress_text %)",
        $progress,
    );

    #  sort by depth so we start from the terminals
    #  and avoid recursion in get_node_range
    my %d;
    foreach my $node (
      sort {($d{$b} //= $b->get_depth) <=> ($d{$a} //= $a->get_depth)}
      values %$nodes) {
        
        my $node_name = $node->get_name;
        if ($return_lists) {
            my $range = $self->get_node_range (
                %args,
                return_list => 1,
                node_ref    => $node,
            );
            my %range_hash;
            @range_hash{@$range} = ();
            $node_range{$node_name} = \%range_hash;
        }
        else {
            my $range = $self->get_node_range (
                %args,
                node_ref => $node,
            );
            if (defined $range) {
                $node_range{$node_name} = $range;
            }
        }
        $count ++;
        #  fewer progress calls as we get heaps with large data sets
        if (not $count % 20) {  
            $progress      = $count / $to_do;
            $progress_text = int (100 * $progress);
            $progress_bar->update(
                "Calculating node ranges\n($count of $to_do)",
                $progress,
            );
        }
    }

    my %results = (node_range => \%node_range);

    return wantarray ? %results : \%results;
}


sub get_node_range {
    my $self = shift;
    my %args = @_;

    my $node_ref = $args{node_ref} || croak "node_ref arg not specified\n";
    my $bd = $args{basedata_ref} || $self->get_basedata_ref;
    
    #  sometimes a child node has the full set,
    #  so there is no need to keep collating
    my $max_poss_group_count = $bd->get_group_count;

    my $return_count = !wantarray && !$args{return_list};

    my $cache_name = 'NODE_RANGE_LISTS';
    my $cache      = $self->get_cached_value_dor_set_default_aa ($cache_name, {});

    if (my $groups = $cache->{$node_ref}) {
        return scalar keys %$groups if $return_count;
        return wantarray ? %$groups : [keys %$groups];
    }

    my $node_name = $node_ref->get_name;
    my %groups;

    my $children = $node_ref->get_children // [];

    if (  !$node_ref->is_internal_node && $bd->exists_label_aa($node_name)) {
        my $gp_list = $bd->get_groups_with_label_as_hash_aa ($node_name);
        if (HAVE_DATA_RECURSIVE) {
            Data::Recursive::hash_merge (\%groups, $gp_list, Data::Recursive::LAZY());
        }
        elsif (HAVE_PANDA_LIB) {
            Panda::Lib::hash_merge (\%groups, $gp_list, Panda::Lib::MERGE_LAZY());
        }
        else {
            @groups{keys %$gp_list} = undef;
        }
    }
    if (scalar @$children && $max_poss_group_count != keys %groups) {
      CHILD:
        foreach my $child (@$children) {
            my $cached_list = $cache->{$child};
            if (!defined $cached_list) {
                #  bodge to work around inconsistent returns
                #  (can be a key count, a hash, or an array ref of keys)
                my $c = $self->get_node_range (node_ref => $child, return_list => 1);
                if (HAVE_DATA_RECURSIVE) {
                    Data::Recursive::hash_merge (\%groups, $c, Data::Recursive::LAZY());
                }
                elsif (HAVE_PANDA_LIB) {
                    Panda::Lib::hash_merge (\%groups, $c, Panda::Lib::MERGE_LAZY());
                }
                else {
                    @groups{@$c} = undef;
                }
            }
            else {
                if (HAVE_DATA_RECURSIVE) {
                    Data::Recursive::hash_merge (\%groups, $cached_list, Data::Recursive::LAZY());
                }
                elsif (HAVE_PANDA_LIB) {
                    Panda::Lib::hash_merge (\%groups, $cached_list, Panda::Lib::MERGE_LAZY());
                }
                else {    
                    @groups{keys %$cached_list} = undef;
                }
            }
            last CHILD if $max_poss_group_count == keys %groups;
        }
    }

    #  Cache by ref because future cases might use the cache
    #  for multiple trees with overlapping name sets.
    $cache->{$node_ref} = \%groups;

    return scalar keys %groups if $return_count;
    return wantarray ? %groups : [keys %groups];
}


sub get_metadata_get_global_node_terminal_count_cache {
    my %metadata = (
        name            => 'get_global_node_terminal_count_cache',
        description     => 'Get a cache for all nodes and their terminal counts',
        pre_calc_global => [],
        indices         => {
            global_node_terminal_count_cache => {
                description => 'Global node terminal count cache',
            }
        }
    );

    return $metadata_class->new(\%metadata);
}

sub get_global_node_terminal_count_cache {
    my $self = shift;

    my %results = (
        global_node_terminal_count_cache => {},
    );
    
    return wantarray ? %results : \%results;
}


sub get_metadata_get_global_node_abundance_hash {
    my %metadata = (
        name            => 'get_global_node_abundance_hash',
        description     => 'Get a hash of all nodes and their corresponding abundances in the basedata',
        pre_calc_global => ['get_trimmed_tree', 'get_node_abundance_global_cache'],
        indices         => {
            global_node_abundance_hash => {
                description => 'Global node abundance hash',
            }
        }
    );

    return $metadata_class->new(\%metadata);
}


sub get_global_node_abundance_hash {
    my $self = shift;
    my %args = @_;

    my $progress_bar = Biodiverse::Progress->new();    

    say '[PD INDICES] Calculating abundance for each node in the tree';

    my $tree  = $args{trimmed_tree} || croak "Argument trimmed_tree missing\n";  
    my $nodes = $tree->get_node_hash;
    my %node_abundance_hash;

    my $to_do = scalar keys %$nodes;
    my $count = 0;

    my $progress = $count / $to_do;
    $progress_bar->update(
        "Calculating node abundances\n($count of $to_do)",
        $progress,
    );

    #  should get terminals and then climb up the tree, adding as we go
    foreach my $node (values %$nodes) {
        #my $node  = $tree->get_node_ref (node => $node_name);
        my $abundance = $self->get_node_abundance_global (
            %args,
            node_ref => $node,
        );
        if (defined $abundance) {
            $node_abundance_hash{$node->get_name} = $abundance;
        }

        $count ++;
        $progress_bar->update(
            "Calculating node abundances\n($count of $to_do)",
            $count / $to_do,
        );
    }

    my %results = (global_node_abundance_hash => \%node_abundance_hash);

    return wantarray ? %results : \%results;
}

sub get_metadata_get_node_abundance_global_cache {
    my %metadata = (
        name            => 'get_node_abundance_global',
        description     => 'Get a cache for the global node abundances',
        indices         => {
            node_abundance_global_cache => {
                description => 'Cache for global node abundances',
            },
        },
    );
    return $metadata_class->new(\%metadata);
}

sub get_node_abundance_global_cache {
    my $self = shift;
  
    my %results = (
        node_abundance_global_cache => {},
    );

    return wantarray ? %results : \%results;
}


sub get_node_abundance_global {
    my $self = shift;
    my %args = @_;

    my $node_ref = $args{node_ref} || croak "node_ref arg not specified\n";
    my $cache = $args{node_abundance_global_cache} // croak 'no node_abundance_global_cache';

    my $bd = $args{basedata_ref} || $self->get_basedata_ref;
    
    my $abundance = 0;
    if ($node_ref->is_terminal_node) {
        $abundance += ($cache->{$node_ref->get_name}
                       //= $bd->get_label_sample_count (element => $node_ref->get_name)
                       );
    }
    else {
        my $children =  $node_ref->get_terminal_elements;
        foreach my $name (keys %$children) {
            $abundance += ($cache->{$name}
                           //= $bd->get_label_sample_count (element => $name)
                          );
        }
    }

    return $abundance;
}


sub get_metadata_get_trimmed_tree {
    my %metadata = (
        name            => 'get_trimmed_tree',
        description     => 'Get a version of the tree trimmed to contain only labels in the basedata',
        required_args   => 'tree_ref',
        indices         => {
            trimmed_tree => {
                description => 'Trimmed tree',
            },
        },
    );
    return $metadata_class->new(\%metadata);
}

#  Create a copy of the current tree, including only those branches
#  which have records in the basedata.
#  This function expects a tree reference as an argument.
#  Returns the original tree ref if all its branches occur in the basedata.
sub get_trimmed_tree {
    my $self = shift;
    my %args = @_;                          

    my $tree = $args{tree_ref};

    my $bd = $self->get_basedata_ref;
    my $lb = $bd->get_labels_ref;
    
    my $terminals  = $tree->get_root_node->get_terminal_elements;  #  should use named nodes?
    my $label_hash = $lb->get_element_hash;

    my (%tmp_combo, %tmp1, %tmp2);
    my $b_score;
    @tmp1{keys %$terminals}  = (1) x scalar keys %$terminals;
    @tmp2{keys %$label_hash} = (1) x scalar keys %$label_hash;
    %tmp_combo = %tmp1;
    @tmp_combo{keys %tmp2}   = (1) x scalar keys %tmp2;

    #  a is common to tree and basedata
    #  b is unique to tree
    #  c is unique to basedata
    #  but we only need b here
    $b_score = scalar (keys %tmp_combo)
       - scalar (keys %tmp2);

    if (!$b_score) {
        say '[PD INDICES] Tree terminals are all basedata labels, no need to trim';
        my %results = (trimmed_tree => $tree);
        return wantarray ? %results : \%results;
    }

    #  keep only those that match the basedata object
    say '[PD INDICES] Creating a trimmed tree by removing clades not present in the basedata';
    my $trimmed_tree = $tree->clone;
    $trimmed_tree->trim (keep => scalar $bd->get_labels);
    my $name = $trimmed_tree->get_param('NAME') // 'noname';
    $trimmed_tree->rename(new_name => $name . ' trimmed');

    my %results = (trimmed_tree => $trimmed_tree);

    return wantarray ? %results : \%results;
}

sub get_metadata_get_last_shared_ancestor_from_subtree {
    my $self = shift;

    my %metadata = (
        name          => 'get_last_shared_ancestor_from_subtree',
        description   => 'get the last shared ancestor for a subtree',
        pre_calc      => ['get_sub_tree_as_hash'],
    );

    return $metadata_class->new(\%metadata);
}

sub get_last_shared_ancestor_from_subtree {
    my ($self, %args) = @_;
    
    my $tree_ref = $args{tree_ref};
    \my %sub_tree = $args{SUBTREE_AS_HASH};
    my $current
      = $tree_ref->get_root_node(tree_has_one_root_node => 1)
                 ->get_name;

    if (keys %sub_tree) {
        #  the subtree has only labels from the current set,
        #  so we only need to find the last branch with one child
        while (@{$sub_tree{$current}} == 1) {
            $current = @{$sub_tree{$current}}[0];
        }
    }

    my $results = {LAST_SHARED_ANCESTOR_SUBTREE => $current};
  
    return wantarray ? %$results : $results;
}


sub get_metadata_get_sub_tree {
    my $self = shift;

    my %metadata = (
        name          => 'get_sub_tree',
        description   => 'get a tree that is a subset of the main tree, e.g. for the set of nodes in a neighbour set',
        required_args => 'tree_ref',
        pre_calc      => ['calc_labels_on_tree'],
    );

    return $metadata_class->new(\%metadata);
}


#  get a tree that is a subset of the main tree,
#  e.g. for the set of nodes in a neighbour set
sub get_sub_tree {
    my $self = shift;
    my %args = @_;

    my $tree       = $args{tree_ref};
    my $label_list = $args{labels} // $args{PHYLO_LABELS_ON_TREE};

    #  Could devise a better naming scheme,
    #  but element lists can be too long to be workable
    #  and abbreviations will be ambiguous in many cases
    my $subtree = blessed ($tree)->new (NAME => 'subtree');

    my $root_name;
    my %added_nodes;
    my %children_to_add;

  LABEL:
    foreach my $label (keys %$label_list) {
        my $node_ref = eval {$tree->get_node_ref_aa ($label)};
        next LABEL if !defined $node_ref;  # not a tree node name

        my $st_node_ref = $subtree->add_node (
            node_ref => $node_ref->duplicate_minimal(),
            name     => $label,
        );
        $added_nodes{$label} = $st_node_ref;
        my $last;

      NODE_IN_PATH:
        while (my $parent = $node_ref->get_parent()) {

            my $parent_name = $parent->get_name;
            my $st_parent = $added_nodes{$parent_name};

            #  we have the rest of the path in this case
            $last = defined $st_parent;

            if (!$last) {
                $st_parent = $subtree->add_node (
                    node_ref => $parent->duplicate_minimal(),
                    name     => $parent_name,
                );
                $added_nodes{$parent_name} = $st_parent;
            }
            my $child_array = $children_to_add{$parent_name} //= [];
            push @$child_array, $st_node_ref;

            last NODE_IN_PATH if $last;

            $node_ref    = $parent;
            $st_node_ref = $st_parent;
        }
    }

    #  do them as a batch to avoid single child calls
    foreach my $parent_name (keys %children_to_add) {
        my $st_parent = $added_nodes{$parent_name};
        $st_parent->add_children (
            #  checking for existing parents takes time
            are_orphans  => 1,  
            is_treenodes => 1,
            children     => $children_to_add{$parent_name},
        );
    }


    my %results = (SUBTREE => $subtree);

    return wantarray ? %results : \%results;
}

sub get_metadata_get_sub_tree_as_hash {
    my $self = shift;

    my %metadata = (
        name          => 'get_sub_tree_as_hash',
        description
          => 'get a hash represention of a tree that is '
           . 'a subset of the main tree, e.g. for the set '
           . 'of nodes in a neighbour set',
        required_args => 'tree_ref',
        pre_calc      => ['calc_labels_on_tree'],
    );

    return $metadata_class->new(\%metadata);
}


#  get a tree that is a subset of the main tree,
#  e.g. for the set of nodes in a neighbour set
sub get_sub_tree_as_hash {
    my $self = shift;
    my %args = @_;

    my $tree       = $args{tree_ref};
    my $label_list = $args{labels} // $args{PHYLO_LABELS_ON_TREE};
    
    \my %parent_hash = $tree->get_node_name_parent_hash;

    my %subtree;
    my $root_name;

  LABEL:
    foreach my $label (grep {exists $parent_hash{$_}} keys %$label_list) {

        $subtree{$label} = [];
        my $node_name   = $label;
        my $parent_name = $parent_hash{$label};
        my $last;

      NODE_IN_PATH:
        while (defined $parent_name) {

            #  we have the rest of the path in this case
            $last = defined $subtree{$parent_name};

            my $child_array = $subtree{$parent_name} //= [];
            push @$child_array, $node_name;

            last NODE_IN_PATH if $last;

            $node_name   = $parent_name;
            $parent_name = $parent_hash{$node_name};
        }
    }

    my %results = (SUBTREE_AS_HASH => \%subtree);

    return wantarray ? %results : \%results;
}

sub get_metadata_get_labels_not_on_tree {
    my $self = shift;

    my %metadata = (
        name          => 'get_labels_not_on_tree',
        description   => 'Hash of the basedata labels that are not on the tree',
        required_args => 'tree_ref',
        indices       => {
            labels_not_on_tree => {
                description => 'Hash of the basedata labels that are not on the tree',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_labels_not_on_tree {
    my $self = shift;
    my %args = @_;                          

    my $bd   = $self->get_basedata_ref;
    my $tree = $args{tree_ref};
    
    my $labels = $bd->get_labels;
    
    my @not_in_tree = grep { !$tree->exists_node_name_aa ($_) } @$labels;

    my %hash;
    @hash{@not_in_tree} = (1) x scalar @not_in_tree;

    my %results = (labels_not_on_tree => \%hash);

    return wantarray ? %results : \%results;
}


sub get_metadata_get_trimmed_tree_as_matrix {
    my $self = shift;

    my %metadata = (
        name            => 'get_trimmed_tree_as_matrix',
        description     => 'Get the trimmed tree as a matrix',
        pre_calc_global => ['get_trimmed_tree'],
    );

    return $metadata_class->new(\%metadata);
}

sub get_trimmed_tree_as_matrix {
    my $self = shift;
    my %args = @_;

    my $mx = $args{trimmed_tree}->to_matrix (class => $mx_class_for_trees);

    my %results = (TRIMMED_TREE_AS_MATRIX => $mx);

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_phylo_sorenson {
    
    my %metadata = (
        name           =>  'Phylo Sorenson',
        type           =>  'Phylogenetic Turnover',  #  keeps it clear of the other indices in the GUI
        description    =>  "Sorenson phylogenetic dissimilarity between two sets of taxa, represented by spanning sets of branches\n",
        reference      => 'Bryant et al. (2008) https://doi.org/10.1073/pnas.0801920105',
        pre_calc       =>  'calc_phylo_abc',
        uses_nbr_lists =>  2,  #  how many sets of lists it must have
        indices        => {
            PHYLO_SORENSON => {
                cluster     =>  'NO_CACHE_ABC',
                distribution => 'unit_interval',
                bounds      =>  [0,1],
                formula     =>  [
                    '1 - (2A / (2A + B + C))',
                    ' where A is the length of shared branches, '
                    . 'and B and C are the length of branches found only in neighbour sets 1 and 2'
                ],
                description => 'Phylo Sorenson score',
                cluster_can_lump_zeroes => 1,
            }
        },
        required_args => {'tree_ref' => 1}
    );

    return $metadata_class->new(\%metadata); 
}

# calculate the phylogenetic Sorenson dissimilarity index between two label lists.
sub calc_phylo_sorenson {

    my $self = shift;
    my %args = @_;

    my ($A, $B, $C, $ABC) = @args{qw /PHYLO_A PHYLO_B PHYLO_C PHYLO_ABC/};

    my $val;
    if ($A || ($B && $C)) {  #  sum of each side must be non-zero
        $val = eval {1 - (2 * $A / ($A + $ABC))};
    }

    my %results = (PHYLO_SORENSON => $val);

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_jaccard {

    my %metadata = (
        name           =>  'Phylo Jaccard',
        type           =>  'Phylogenetic Turnover',
        description    =>  "Jaccard phylogenetic dissimilarity between two sets of taxa, represented by spanning sets of branches\n",
        reference      => 'Lozupone and Knight (2005) https://doi.org/10.1128/AEM.71.12.8228-8235.2005',
        pre_calc       =>  'calc_phylo_abc',
        uses_nbr_lists =>  2,  #  how many sets of lists it must have
        indices        => {
            PHYLO_JACCARD => {
                cluster     =>  'NO_CACHE_ABC',
                distribution => 'unit_interval',
                bounds      =>  [0,1],
                formula     =>  [
                    '= 1 - (A / (A + B + C))',
                    ' where A is the length of shared branches, '
                    . 'and B and C are the length of branches found only in neighbour sets 1 and 2',
                ],
                description => 'Phylo Jaccard score',
                cluster_can_lump_zeroes => 1,
            }
        },
        required_args => {'tree_ref' => 1}
    );

    return $metadata_class->new(\%metadata);
}

# calculate the phylogenetic Sorenson dissimilarity index between two label lists.
sub calc_phylo_jaccard {
    my $self = shift;
    my %args = @_;

    my ($A, $B, $C, $ABC) = @args{qw /PHYLO_A PHYLO_B PHYLO_C PHYLO_ABC/};  

    my $val;
    if ($A || ($B && $C)) {  #  sum of each side must be non-zero
        $val = eval {1 - ($A / $ABC)};
    }    

    my %results = (PHYLO_JACCARD => $val);

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_s2 {

    my %metadata = (
        name           =>  'Phylo S2',
        type           =>  'Phylogenetic Turnover',
        description    =>  "S2 phylogenetic dissimilarity between two sets of taxa, represented by spanning sets of branches\n",
        pre_calc       =>  'calc_phylo_abc',
        uses_nbr_lists =>  2,  #  how many sets of lists it must have
        indices        => {
            PHYLO_S2 => {
                cluster     =>  'NO_CACHE_ABC',
                formula     =>  [
                    '= 1 - (A / (A + min (B, C)))',
                    ' where A is the sum of shared branch lengths, '
                    . 'and B and C are the sum of branch lengths found'
                    . 'only in neighbour sets 1 and 2',
                ],
                description => 'Phylo S2 score',
                distribution => 'unit_interval',
                bounds       => [0, 1],
                #  min (B,C) in denominator means cluster order
                #  influences tie breaker results as different
                #  assemblages are merged
                cluster_can_lump_zeroes => 0,
            }
        },
        required_args => {'tree_ref' => 1}
    );

    return $metadata_class->new(\%metadata);
}

# calculate the phylogenetic S2 dissimilarity index between two label lists.
sub calc_phylo_s2 {
    my $self = shift;
    my %args = @_;

    my ($A, $B, $C) = @args{qw /PHYLO_A PHYLO_B PHYLO_C/};  

    my $val;
    if ($A || ($B && $C)) {  #  sum of each side must be non-zero
        $val = eval {1 - ($A / ($A + min ($B, $C)))};
    }

    my %results = (PHYLO_S2 => $val);

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_abc {
    
    my %metadata = (
        name            =>  'Phylogenetic ABC',
        description     =>  'Calculate the shared and not shared branch lengths between two sets of labels',
        type            =>  'Phylogenetic Turnover',
        # pre_calc        =>  [qw /_calc_phylo_abc_lists calc_abc/],
        pre_calc        =>  [qw /calc_abc/],
        pre_calc_global =>  [qw /get_trimmed_tree get_path_length_cache set_path_length_cache_by_group_flag/],
        uses_nbr_lists  =>  2,  #  how many sets of lists it must have
        indices         => {
            PHYLO_A => {
                description  =>  'Sum of branch lengths shared by labels in nbr sets 1 and 2',
                lumper       => 1,
            },
            PHYLO_B => {
                description  =>  'Sum of branch lengths unique to labels in nbr set 1',
                lumper       => 0,
            },
            PHYLO_C => {
                description  =>  'Sum of branch lengths unique to labels in nbr set 2',
                lumper       => 0,
            },
            PHYLO_ABC => {
                description  =>  'Sum of branch lengths associated with labels in nbr sets 1 and 2',
                lumper       => 1,
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_abc {
    my $self = shift;
    my %args = @_;

    my $tree = $args{trimmed_tree};

    # get_path_lengths_to_root_node also caches but this way we
    # avoid sub overheads when building a large matrix
    state $cache_name = '_calc_pd_abc_path_lengths';
    my $cache = $self->get_cached_value_dor_set_default_href($cache_name);

    my @nodes_in_path;

    my $i = 0;
    my @label_hash_names = qw/label_hash1 label_hash2/;
    unshift @label_hash_names, ''; # keep in synch
    BY_LIST:
    foreach my $list_name (qw/element_list1 element_list2/) {
        $i++; #  start at 1 so we match the numbered names
        my $el_list = $args{$list_name} // next BY_LIST;
        my @elements = keys %$el_list;
        my $have_cache = (@elements == 1 && $cache->{$elements[0]});
        $nodes_in_path[$i]
            = (@elements == 0)
            ? {}
            : $have_cache
            ? $cache->{$elements[0]}
            : $self->get_path_lengths_to_root_node(
                %args,
                labels   => $args{$label_hash_names[$i]},
                tree_ref => $tree,
                el_list  => \@elements,
            );
        $cache->{$elements[0]} = $nodes_in_path[$i]
            if @elements == 1;
    }

    \my %list1 = $nodes_in_path[1];
    \my %list2 = $nodes_in_path[2];
    my ($aa, $bb, $cc) = (0, 0, 0);

    if ($self->get_pairwise_mode) {
        #  we can cache the sums of branch lengths and thus
        #  simplify the calcs as we only need to find $aa
        my $cache
          = $self->get_cached_value_dor_set_default_href ('_calc_phylo_abc_pairwise_branch_sum_cache');
        my $sum_i = $cache->{(keys %{$args{element_list1}})[0]}  # use postfix deref?
            //= (sum values %list1) // 0;
        my $sum_j = $cache->{(keys %{$args{element_list2}})[0]}
            //= (sum values %list2) // 0;
        #  save some looping, mainly when there are large differences in key counts
        if (keys %list1 <= keys %list2) {
            $aa += $list1{$_} foreach grep {exists $list2{$_}} keys %list1;
        }
        else {
            $aa += $list2{$_} foreach grep {exists $list1{$_}} keys %list2;
        }
        #  Avoid precision issues later when $aa is
        #  essentially zero given numeric precision
        $aa ||= 0;
        $bb = $sum_i - $aa;
        $cc = $sum_j - $aa;
    }
    else {
        #  non-pairwise mode so we cannot usefully cache the sums
        foreach my $key (keys %list1) {
            exists $list2{$key}
                ? ($aa += $list1{$key})
                : ($bb += $list1{$key});
        }
        #  postfix for speed
        $cc += $list2{$_}
            foreach grep {!exists $list1{$_}} keys %list2;
    }

    my %results = (
        PHYLO_A   => $aa,
        PHYLO_B   => $bb,
        PHYLO_C   => $cc,
        PHYLO_ABC => $aa + $bb + $cc,
    );

    return wantarray ? %results : \%results;
}



sub get_metadata__calc_phylo_abc_lists {

    my %metadata = (
        name            =>  'Phylogenetic ABC lists',
        description     =>  'Calculate the sets of shared and not shared branches between two sets of labels',
        type            =>  'Phylogenetic Indices',
        pre_calc        =>  'calc_abc',
        pre_calc_global =>  [qw /get_trimmed_tree get_path_length_cache set_path_length_cache_by_group_flag/],
        uses_nbr_lists  =>  1,  #  how many sets of lists it must have
        required_args   => {tree_ref => 1},
    );

    return $metadata_class->new(\%metadata);
}

sub _calc_phylo_abc_lists {
    my $self = shift;
    my %args = @_;

    my $label_hash1 = $args{label_hash1};
    my $label_hash2 = $args{label_hash2};

    my $tree = $args{trimmed_tree};

    my $nodes_in_path1 = $self->get_path_lengths_to_root_node (
        %args,
        labels   => $label_hash1,
        tree_ref => $tree,
        el_list  => [keys %{$args{element_list1}}],
    );

    my $nodes_in_path2 = scalar %{$args{element_list2}}
        ? $self->get_path_lengths_to_root_node (
            %args,
            labels   => $label_hash2,
            tree_ref => $tree,
            el_list  => [keys %{$args{element_list2}}],
        )
        : {};

    my %results;
    #  one day we can clean this all up
    if (HAVE_BD_UTILS) {
        my $res = Biodiverse::Utils::get_hash_shared_and_unique (
            $nodes_in_path1,
            $nodes_in_path2,
        );
        @results{qw /PHYLO_A_LIST PHYLO_B_LIST PHYLO_C_LIST/}
          = @$res{qw /a b c/};
    }
    else {
        my %A;
        if (HAVE_DATA_RECURSIVE) {
            Data::Recursive::hash_merge (\%A, $nodes_in_path1, Data::Recursive::LAZY());
            Data::Recursive::hash_merge (\%A, $nodes_in_path2, Data::Recursive::LAZY());
        }
        elsif (HAVE_PANDA_LIB) {
            Panda::Lib::hash_merge (\%A, $nodes_in_path1, Panda::Lib::MERGE_LAZY());
            Panda::Lib::hash_merge (\%A, $nodes_in_path2, Panda::Lib::MERGE_LAZY());
        }
        else {
            %A = (%$nodes_in_path1, %$nodes_in_path2);
        }
    
        # create a new hash %B for nodes in label hash 1 but not 2
        # then get length of B
        my %B = %A;
        delete @B{keys %$nodes_in_path2};
    
        # create a new hash %C for nodes in label hash 2 but not 1
        # then get length of C
        my %C = %A;
        delete @C{keys %$nodes_in_path1};
    
        # get length of %A = branches not in %B or %C
        delete @A{keys %B, keys %C};
    
         @results{qw /PHYLO_A_LIST PHYLO_B_LIST PHYLO_C_LIST/}
           = (\%A, \%B, \%C);
    }

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_corrected_weighted_endemism{
    
    my $descr = 'Corrected weighted endemism.  '
              . 'This is the phylogenetic analogue of corrected '
              . 'weighted endemism.';

    my %metadata = (
        name            => 'Corrected weighted phylogenetic endemism',
        description     => q{What proportion of the PD is range-restricted to this neighbour set?},
        type            => 'Phylogenetic Endemism Indices',
        pre_calc        => [qw /calc_pe calc_pd/],
        uses_nbr_lists  =>  1,
        reference       => '',
        indices         => {
            PE_CWE => {
                description => $descr,
                reference   => '',
                formula     => [ 'PE\_WE / PD' ],
                distribution => 'unit_interval',
                bounds       => [0, 1],
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_corrected_weighted_endemism {
    my $self = shift;
    my %args = @_;

    my $pe = $args{PE_WE};
    my $pd = $args{PD};
    no warnings 'uninitialized';

    my %results = (
        PE_CWE => $pd ? $pe / $pd : undef,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_corrected_weighted_rarity {
    
    my $descr = 'Corrected weighted phylogenetic rarity.  '
              . 'This is the phylogenetic rarity analogue of corrected '
              . 'weighted endemism.';

    my %metadata = (
        name            =>  'Corrected weighted phylogenetic rarity',
        description     =>  q{What proportion of the PD is abundance-restricted to this neighbour set?},
        type            =>  'Phylogenetic Endemism Indices',
        pre_calc        => [qw /_calc_phylo_aed_t calc_pd/],
        uses_nbr_lists  =>  1,
        reference       => '',
        indices         => {
            PHYLO_RARITY_CWR => {
                description => $descr,
                reference   => '',
                formula     => [ 'AED_T / PD' ],
                distribution => 'unit_interval',
                bounds       => [0, 1],
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_corrected_weighted_rarity {
    my $self = shift;
    my %args = @_;

    my $aed_t = $args{PHYLO_AED_T};
    my $pd    = $args{PD};
    no warnings 'uninitialized';

    my %results = (
        PHYLO_RARITY_CWR => $pd ? $aed_t / $pd : undef,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_aed_t {
    
    my $descr = 'Abundance weighted ED_t '
              . '(sum of values in PHYLO_AED_LIST times their abundances).'
              . ' This is equivalent to a phylogenetic rarity score '
              . '(see phylogenetic endemism)';

    my %metadata = (
        name            =>  'Evolutionary distinctiveness per site',
        description     =>  'Site level evolutionary distinctiveness',
        type            =>  'Phylogenetic Indices',
        pre_calc        => [qw /_calc_phylo_aed_t/],
        uses_nbr_lists  =>  1,
        reference    => 'Cadotte & Davies (2010) https://doi.org/10.1111/j.1472-4642.2010.00650.x',
        indices         => {
            PHYLO_AED_T => {
                description  => $descr,
                reference    => 'Cadotte & Davies (2010) https://doi.org/10.1111/j.1472-4642.2010.00650.x',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_aed_t {
    my $self = shift;
    my %args = @_;

    my %results = (PHYLO_AED_T => $args{PHYLO_AED_T});

    return wantarray ? %results : \%results;
}

sub get_metadata_calc_phylo_aed_t_wtlists {
    my %metadata = (
        name            =>  'Evolutionary distinctiveness per terminal taxon per site',
        description     =>  'Site level evolutionary distinctiveness per terminal taxon',
        type            =>  'Phylogenetic Indices',
        pre_calc        => [qw /_calc_phylo_aed_t/],
        uses_nbr_lists  =>  1,
        reference    => 'Cadotte & Davies (2010) https://doi.org/10.1111/j.1472-4642.2010.00650.x',
        indices         => {
            PHYLO_AED_T_WTLIST => {
                description  => 'Abundance weighted ED per terminal taxon '
                              . '(the AED score of each taxon multiplied by its '
                              . 'abundance in the sample)',
                reference    => 'Cadotte & Davies (2010) https://doi.org/10.1111/j.1472-4642.2010.00650.x',
                type         => 'list',
            },
            PHYLO_AED_T_WTLIST_P => {
                description  => 'Proportional contribution of each terminal taxon to the AED_T score',
                reference    => 'Cadotte & Davies (2010) https://doi.org/10.1111/j.1472-4642.2010.00650.x',
                type         => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_aed_t_wtlists {
    my $self = shift;
    my %args = @_;

    my $wt_list   = $args{PHYLO_AED_T_WTLIST};
    my $aed_t     = $args{PHYLO_AED_T};
    my $p_wt_list = {};

    foreach my $label (keys %$wt_list) {
        $p_wt_list->{$label} = $wt_list->{$label} / $aed_t;
    }

    my %results = (
        PHYLO_AED_T_WTLIST   => $wt_list,
        PHYLO_AED_T_WTLIST_P => $p_wt_list,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata__calc_phylo_aed_t {
    my %metadata = (
        name            => '_calc_phylo_aed_t',
        description     => 'Inner sub for AED_T calcs',
        pre_calc        => [qw /calc_abc3 calc_phylo_aed/],
        uses_nbr_lists  =>  1,
    );

    return $metadata_class->new(\%metadata);
}

sub _calc_phylo_aed_t {
    my $self = shift;
    my %args = @_;

    my $aed_hash   = $args{PHYLO_AED_LIST};
    my $label_hash = $args{label_hash_all};
    my $aed_t;
    my %scores;

  LABEL:
    foreach my $label (keys %$label_hash) {
        my $abundance = $label_hash->{$label};

        next LABEL if !exists $aed_hash->{$label};

        my $aed_score = $aed_hash->{$label};
        my $weight    = $abundance * $aed_score;

        $scores{$label} = $weight;
        $aed_t += $weight;
    }

    my %results = (
        PHYLO_AED_T        => $aed_t,
        PHYLO_AED_T_WTLIST => \%scores,
    );

    return wantarray ? %results : \%results;
}


sub get_metadata_calc_phylo_aed {
    my $descr = "Evolutionary distinctiveness metrics (AED, ED, ES)\n"
                . 'Label values are constant for all '
                . 'neighbourhoods in which each label is found. ';

    my %metadata = (
        name            =>  'Evolutionary distinctiveness',
        description     =>  $descr,
        type            =>  'Phylogenetic Indices',
        pre_calc        => [qw /calc_abc/],
        pre_calc_global => [qw /get_aed_scores/],
        uses_nbr_lists  =>  1,
        reference    => 'Cadotte & Davies (2010) https://doi.org/10.1111/j.1472-4642.2010.00650.x',
        indices         => {
            PHYLO_AED_LIST => {
                description  =>  'Abundance weighted ED per terminal label',
                type         => 'list',
                reference    => 'Cadotte & Davies (2010) https://doi.org/10.1111/j.1472-4642.2010.00650.x',
            },
            PHYLO_ES_LIST => {
                description  =>  'Equal splits partitioning of PD per terminal label',
                type         => 'list',
                reference    => 'Redding & Mooers (2006) https://doi.org/10.1111%2Fj.1523-1739.2006.00555.x',
            },
            PHYLO_ED_LIST => {
                description  =>  q{"Fair proportion" partitioning of PD per terminal label},
                type         => 'list',
                reference    => 'Isaac et al. (2007) https://doi.org/10.1371/journal.pone.0000296',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}


sub calc_phylo_aed {
    my $self = shift;
    my %args = @_;

    my $label_hash = $args{label_hash_all};
    my $es_wts     = $args{ES_SCORES};
    my $ed_wts     = $args{ED_SCORES};
    my $aed_wts    = $args{AED_SCORES};

    my (%es, %ed, %aed);
    # now loop over the terminals and extract the weights (would slices be faster?)
    # Do we want the proportional values?  Divide by PD to get them.
  LABEL:
    foreach my $label (keys %$label_hash) {
        next LABEL if !exists $aed_wts->{$label};
        $aed{$label} = $aed_wts->{$label};
        $ed{$label}  = $ed_wts->{$label};
        $es{$label}  = $es_wts->{$label};
    }

    my %results = (
        PHYLO_ES_LIST  => \%es,
        PHYLO_ED_LIST  => \%ed,
        PHYLO_AED_LIST => \%aed,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_get_aed_scores {

    my %metadata = (
        name            => 'get_aed_scores',
        description     => 'A hash of the ES, ED and BED scores for each label',
        pre_calc        => [qw /calc_abc/],
        pre_calc_global => [
            qw /get_trimmed_tree
                get_global_node_abundance_hash
                get_global_node_terminal_count_cache
              /],
        indices         => {
            ES_SCORES => {
                description => 'Hash of ES scores for each label'
            },
            ED_SCORES => {
                description => 'Hash of ED scores for each label'
            },
            AED_SCORES => {
                description => 'Hash of AED scores for each label'
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub get_aed_scores {
    my $self = shift;
    my %args = @_;

    my $tree = $args{trimmed_tree};
    my $node_abundances = $args{global_node_abundance_hash};
    my $terminal_count_cache = $args{global_node_terminal_count_cache};
    my (%es_wts, %ed_wts, %aed_wts);
    my $terminal_elements = $tree->get_root_node->get_terminal_elements;

    LABEL:
    foreach my $label (keys %$terminal_elements) {

        #  check if node exists - should use a pre_calc
        my $node_ref = eval {
            $tree->get_node_ref (node => $label);
        };
        if (my $e = $EVAL_ERROR) {  #  still needed? 
            next LABEL if Biodiverse::Tree::NotExistsNode->caught;
            croak $e;
        }

        my $length  = $node_ref->get_length;
        my $es_sum  = $length;
        my $ed_sum  = $length;
        my $aed_sum = eval {$length / $node_abundances->{$label}};
        my $es_wt  = 1;
        my ($ed_wt, $aed_wt);
        #my $aed_label_count = $node_abundances->{$label};

      TRAVERSE_TO_ROOT:
        while ($node_ref = $node_ref->get_parent) {
            my $node_len = $node_ref->get_length;
            my $name     = $node_ref->get_name;

            $es_wt  /= $node_ref->get_child_count;  #  es uses a cumulative scheme
            $ed_wt  =  1 / ($terminal_count_cache->{$name}
                            //= $node_ref->get_terminal_element_count
                            );
            $aed_wt =  1 / $node_abundances->{$name};

            $es_sum  += $node_len * $es_wt;
            $ed_sum  += $node_len * $ed_wt;
            $aed_sum += $node_len * $aed_wt;
        }

        $es_wts{$label}  = $es_sum;
        $ed_wts{$label}  = $ed_sum;
        $aed_wts{$label} = $aed_sum;
    }

    my %results = (
        ES_SCORES  => \%es_wts,
        ED_SCORES  => \%ed_wts,
        AED_SCORES => \%aed_wts,
    );

    return wantarray ? %results : \%results;
}

sub get_metadata_get_tree_node_length_hash {
    my %metadata = (
        name            => 'get_tree_node_length_hash',
        description     => 'A hash of the node lengths, indexed by node name',
        required_args   => qw /tree_ref/,
        indices         => {
            TREE_NODE_LENGTH_HASH => {
                description => 'Hash of node lengths, indexed by node name',
                type        => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}


sub get_tree_node_length_hash {
    my $self = shift;
    my %args = @_;
    
    my $tree_ref = $args{tree_ref} // croak 'Missing tree_ref arg';
    my $node_hash = $tree_ref->get_node_hash;
    
    my %len_hash;
    foreach my $node_name (keys %$node_hash) {
        my $node_ref = $node_hash->{$node_name};
        my $length   = $node_ref->get_length;
        $len_hash{$node_name} = $length;
    }
    
    my %results = (TREE_NODE_LENGTH_HASH => \%len_hash);

    return wantarray ? %results : \%results;
}



sub get_metadata_calc_phylo_abundance {

    my %metadata = (
        description     => 'Phylogenetic abundance based on branch '
                           . "lengths back to the root of the tree.\n"
                           . 'Uses labels in both neighbourhoods.',
        name            => 'Phylogenetic Abundance',
        type            => 'Phylogenetic Indices',
        pre_calc        => [qw /_calc_pd calc_abc3 calc_labels_on_tree/],
        pre_calc_global => [qw /get_trimmed_tree get_global_node_abundance_hash/],
        uses_nbr_lists  => 1,  #  how many lists it must have
        distribution => 'nonnegative',
        indices         => {
            PHYLO_ABUNDANCE   => {
                cluster       => undef,
                description   => 'Phylogenetic abundance',
                reference     => '',
                formula       => [
                    '= \sum_{c \in C} A \times L_c',
                    ' where ',
                    'C',
                    'is the set of branches in the minimum spanning path '
                     . 'joining the labels in both neighbour sets to the root of the tree,',
                     'c',
                    ' is a branch (a single segment between two nodes) in the '
                    . 'spanning path ',
                    'C',
                    ', and ',
                    'L_c',
                    ' is the length of branch ',
                    'c',
                    ', and ',
                    'A',
                    ' is the abundance of that branch (the sum of its descendant label abundances).'
                ],
            },
            PHYLO_ABUNDANCE_BRANCH_HASH => {
                cluster       => undef,
                description   => 'Phylogenetic abundance per branch',
                reference     => '',
                type => 'list',
            },
        },
    );

    return $metadata_class->new(\%metadata);
}

sub calc_phylo_abundance {
    my $self = shift;
    my %args = @_;
    
    my $named_labels   = $args{PHYLO_LABELS_ON_TREE};
    my $abundance_hash = $args{label_hash_all};
    my $tree           = $args{trimmed_tree};

    my %pd_abundance_hash;
    my $pd_abundance;

    LABEL:
    foreach my $label (keys %$named_labels) {

        my $node_ref     = $tree->get_node_ref_aa ($label);
        my $path_lengths = $node_ref->get_path_lengths_to_root_node;
        my $abundance    = $abundance_hash->{$label};
        
        foreach my $node_name (keys %$path_lengths) {
            my $val = $abundance * $path_lengths->{$node_name};
            $pd_abundance_hash{$node_name} += $val;
            $pd_abundance += $val;
        }
    }    

    my %results = (
        PHYLO_ABUNDANCE => $pd_abundance,
        PHYLO_ABUNDANCE_BRANCH_HASH => \%pd_abundance_hash,
    );

    return wantarray ? %results : \%results;
}

1;


__END__

=head1 NAME

Biodiverse::Indices::Phylogenetic

=head1 SYNOPSIS

  use Biodiverse::Indices;

=head1 DESCRIPTION

Phylogenetic indices for the Biodiverse system.
It is inherited by Biodiverse::Indices and not to be used on it own.

See L<http://purl.org/biodiverse/wiki/Indices> for more details.

=head1 METHODS

=over

=item INSERT METHODS

=back

=head1 REPORTING ERRORS

Use the issue tracker at http://www.purl.org/biodiverse

=head1 COPYRIGHT

Copyright (c) 2010 Shawn Laffan. All rights reserved.  

=head1 LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

For a full copy of the license see <http://www.gnu.org/licenses/>.

=cut
