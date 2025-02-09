=head1 LEGEND

Component to display a legend. 

=cut

package Biodiverse::GUI::Legend;

use 5.010;
use strict;
use warnings;
#use Data::Dumper;
use Carp;
use Scalar::Util qw /blessed/;
use List::Util qw /min max/;
use List::MoreUtils qw /minmax firstidx/;

use experimental qw /refaliasing declared_refs/;

use Gtk2;
use Gnome2::Canvas;
use Tree::R;

#use Geo::ShapeFile;

our $VERSION = '4.99_001';

use Biodiverse::GUI::GUIManager;
use Biodiverse::GUI::CellPopup;
use Biodiverse::BaseStruct;
use Biodiverse::Progress;

require Biodiverse::Config;
my $progress_update_interval = $Biodiverse::Config::progress_update_interval;

##########################################################
# Constants
##########################################################
use constant BORDER_SIZE        => 20;
use constant LEGEND_WIDTH       => 20;
use constant MARK_X_LEGEND_OFFSET  => 0.01;
use constant MARK_Y_LEGEND_OFFSET  => 8;
use constant LEGEND_HEIGHT  => 380;
use constant INDEX_RECT         => 2;  # Canvas (square) rectangle for the cell

use constant COLOUR_BLACK        => Gtk2::Gdk::Color->new(0, 0, 0);
use constant COLOUR_WHITE        => Gtk2::Gdk::Color->new(255*257, 255*257, 255*257);
use constant DARKEST_GREY_FRAC   => 0.2;
use constant LIGHTEST_GREY_FRAC  => 0.8;


#  refactor as state var inside sub when we require a perl version that
#  supports state on lists (5.28)
my %canape_colour_hash = (
    0 => Gtk2::Gdk::Color->parse('lightgoldenrodyellow'),  #  non-sig, lightgoldenrodyellow
    1 => Gtk2::Gdk::Color->parse('red'),                   #  red, neo
    2 => Gtk2::Gdk::Color->parse('royalblue1'),            #  blue, palaeo
    3 => Gtk2::Gdk::Color->parse('#CB7FFF'),               #  purple, mixed
    4 => Gtk2::Gdk::Color->parse('darkorchid'),            #  deep purple, super ('#6A3d9A' is too dark)
);

##########################################################
# Construction
##########################################################

=head2 Constructor

=over 5

=back

=cut

sub new {
    my $class        = shift;
    my %args         = @_;

    my $canvas       = $args{canvas};
    my $legend_marks = $args{legend_marks} // [qw/nw w w sw/];
    my $legend_mode  = $args{legend_mode}  // 'Hue';
    my $width_px     = $args{width_px}     // 0;
    my $height_px    = $args{height_px}    // 0;

    my $self = {
        canvas       => $canvas,
        legend_marks => $legend_marks,
        legend_mode  => $legend_mode,
        width_px     => $width_px,
        height_px    => $height_px,
        hue          => $args{hue} // 0,
    };
    bless $self, $class;
    # Get the width and height of the canvas.
    #my ($width, $height) = $self->{canvas}->c2w($width_px || 0, $height_px || 0);
    my ($width, $height) = $self->{canvas}->c2w($self->{width_px} || 0, $self->{height_px} || 0);

    # Make group so we can pack the coloured
    # rectangles into it.
    $self->{legend_group} = Gnome2::Canvas::Item->new (
        $self->{canvas}->root,
        'Gnome2::Canvas::Group',
        x => $width - $self->get_width,
        y => 0,
    );
    $self->{legend_group}->raise_to_top();

    # Create the legend rectangle.
    $self->{legend} = $self->make_rect();

    #  reverse might not be needed but ensures the array is the correct size from the start
    foreach my $i (reverse 0..3) {
        $self->{marks}[$i] = $self->make_mark($self->{legend_marks}[$i]);
    }
    #  clunky that we need to do it here
    my @anchors = ('nw', ('w') x 3, 'sw');
    foreach my $i (reverse 0..4) {
        $self->{canape_marks}[$i]    = $self->make_mark($anchors[$i]);
        $self->{divergent_marks}[$i] = $self->make_mark($anchors[$i]);
        $self->{ratio_marks}[$i]     = $self->make_mark($anchors[$i]);
    }
    @anchors = ('nw', ('w') x 5, 'sw');
    foreach my $i (reverse 0..6) {
        $self->{zscore_marks}[$i] = $self->make_mark($anchors[$i]);
        $self->{prank_marks}[$i]  = $self->make_mark($anchors[$i]);
    }

    #  debug stuff
    #my $sub = sub {
    #    my $i = 0;
    #    print STDERR "Stack Trace:\n";
    #    while ( (my @call_details = (caller($i++))) ){
    #        print STDERR $call_details[1].":".$call_details[2]." in function ".$call_details[3]."\n";
    #    }
    #};
    #$self->{legend_group}->signal_connect_swapped('hide', $sub, $self);

    return $self;
};

# Hide the legend
sub hide {
    my $self = shift;

    return if !$self->{legend_group};

    # Hide the legend group.
    $self->{legend_group}->hide;

    return;
}

# Show the legend
sub show {
    my $self = shift;

    return if !$self->{legend_group};

    # Show the legend group.
    $self->{legend_group}->show;

    return;
}

# Makes a rectangle and fills it 
# with colours for the chosen legend
# mode.
sub make_rect {
    my $self = shift;
    my ($width, $height);

    # If legend_colours_group already exists then destroy it.
    # We do this because we are about to create it again
    # with a different colour scheme as defined by legend_mode.
    if ($self->{legend_colours_group}) {
        $self->{legend_colours_group}->destroy(); 
    }

    # Make a group so we can pack the coloured
    # rectangles into it to create the legend.
    $self->{legend_colours_group} = Gnome2::Canvas::Item->new (
        $self->{legend_group},
        'Gnome2::Canvas::Group',
        x => 0, 
        y => 0, 
    );   

    # Create and colour the legend according to the colouring
    # scheme specified by $self->{legend_mode}. Each colour
    # mode has a different range as specified by $height.
    # Once the legend is create it is scaled to the height
    # of the canvas in reposition and according to each
    # mode's scaling factor held in $self->{legend_scaling_factor}.

    if ($self->get_canape_mode) {

        ($width, $height) = ($self->get_width, 255);
        $self->{legend_height} = $height;

        my $n = (scalar keys %canape_colour_hash) - 1;
        foreach my $row (0..($height - 1)) {
            my $class = int (0.5 + $n * $row / ($height - 1));
            my $colour = $self->get_colour_canape ($class);
            $self->add_row($self->{legend_colours_group}, $row, $colour);
        }
    }
    elsif ($self->get_zscore_mode) {

        ($width, $height) = ($self->get_width, 255);
        $self->{legend_height} = $height;
        my @dummy_zvals = reverse (-2.6, -2, -1.7, 0, 1.7, 2, 2.6);

        foreach my $row (0..($height - 1)) {
            #  a clunky means of aligning the colours with the labels
            my $scaled =  $row / $height;
            if ($scaled > 0.5) {
                $scaled -= 0.05
            }
            elsif ($scaled < 0.5) {
                $scaled += 0.05
            }
            $scaled = min ($#dummy_zvals, max (0, $scaled));
            my $class = int (@dummy_zvals * $scaled);
            my $colour = $self->get_colour_zscore ($dummy_zvals[$class]);
            $self->add_row($self->{legend_colours_group}, $row, $colour);
        }
    }
    elsif ($self->get_prank_mode) {
        #  cargo culted from above - need to refactor
        ($width, $height) = ($self->get_width, 255);
        $self->{legend_height} = $height;
        my @dummy_vals = reverse (0.001, 0.02, 0.04, 0.5, 0.951, 0.978, 0.991);

        foreach my $row (0..($height - 1)) {
            #  a clunky means of aligning the colours with the labels
            my $scaled =  $row / $height;
            if ($scaled > 0.5) {
                $scaled -= 0.05
            }
            elsif ($scaled < 0.5) {
                $scaled += 0.05
            }
            $scaled = min ($#dummy_vals, max (0, $scaled));
            my $class = int (@dummy_vals * $scaled);
            my $colour = $self->get_colour_prank ($dummy_vals[$class]);
            $self->add_row($self->{legend_colours_group}, $row, $colour);
        }
    }
    elsif ($self->get_ratio_mode) {
        ($width, $height) = ($self->get_width, 180);
        $self->{legend_height} = $height;

        local $self->{log_mode} = 0; # hacky override

        my $mid = ($height - 1) / 2;
        foreach my $row (0..($height - 1)) {
            my $val = $row < $mid ? 1 / ($mid - $row) : $row - $mid;
            #  invert again so colours match legend text
            my $colour = $self->get_colour_ratio (1 / $val, $mid);
            $self->add_row($self->{legend_colours_group}, $row, $colour);
        }
    }
    elsif ($self->get_divergent_mode) {
        ($width, $height) = ($self->get_width, 180);
        $self->{legend_height} = $height;

        local $self->{log_mode} = 0; # hacky override

        my $centre = ($height - 1) / 2;
        my $extreme = $height - $centre;
        foreach my $row (0..($height - 1)) {
            #  ensure colours match plot since 0 is the top
            my $colour = $self->get_colour_divergent ($height - $row, $centre, $extreme);
            $self->add_row($self->{legend_colours_group}, $row, $colour);
        }
    }
    elsif ($self->{legend_mode} eq 'Hue') {

        ($width, $height) = ($self->get_width, 180);
        $self->{legend_height} = $height;

        local $self->{log_mode} = 0; # hacky override

        foreach my $row (0..($height - 1)) {
            my $colour = $self->get_colour_hue ($height - $row, 0, $height-1);
            $self->add_row($self->{legend_colours_group}, $row, $colour);
        }

    }
    elsif ($self->{legend_mode} eq 'Sat') {

        ($width, $height) = ($self->get_width, 100);
        $self->{legend_height} = $height;

        local $self->{log_mode} = 0; # hacky override

        foreach my $row (0..($height - 1)) {
            my $colour = $self->get_colour_saturation ($height - $row, 0, $height-1);
            $self->add_row($self->{legend_colours_group}, $row, $colour);
        }
    }
    elsif ($self->{legend_mode} eq 'Grey') {

        ($width, $height) = ($self->get_width, 255);
        $self->{legend_height} = $height;

        local $self->{log_mode} = 0; # hacky override

        foreach my $row (0..($height - 1)) {
            my $colour = $self->get_colour_grey ($height - $row, 0, $height-1);
            $self->add_row($self->{legend_colours_group}, $row, $colour);
        }
    }
    else {
        croak "Legend: Invalid colour system $self->{legend_mode}\n";
    }

    return $self->{legend_colours_group};
}

# Add a coloured row to the legend.
sub add_row {
    my ($self, $group, $row, $r, $g, $b) = @_;

    my $width = $self->get_width;
    
    my $colour = blessed ($r) && $r->isa('Gtk2::Gdk::Color')
      ? $r
      : Gtk2::Gdk::Color->new($r,$g,$b);

    my $legend_colour_row = Gnome2::Canvas::Item->new (
        $group,
        'Gnome2::Canvas::Rect',
        x1 => 0,
        x2 => $width,
        y1 => $row,
        y2 => $row+1,
        fill_color_gdk => $colour,
    );
}

##########################################################
# Setting up various components of the legend 
##########################################################

sub make_mark {
    my $self   = shift;
    my $anchor = shift // 'w';
    my $mark = Gnome2::Canvas::Item->new (
        $self->{legend_group}, 
        'Gnome2::Canvas::Text',
        text            => q{0},
        anchor          => $anchor,
        fill_color_gdk  => COLOUR_BLACK,
    );

    $mark->raise_to_top();

    return $mark;
}

sub set_gt_flag {
    my $self = shift;
    my $flag = shift;
    $self->{legend_gt_flag} = $flag;
    return;
}

sub set_lt_flag {
    my $self = shift;
    my $flag = shift;
    $self->{legend_lt_flag} = $flag;
    return;
}

sub set_width {
    my ($self, $width) = @_;
    $self->{back_rect_width} = $width;
}

sub get_width {
    my $self = shift;
    return $self->{back_rect_width} // LEGEND_WIDTH;
}

sub get_height {
    my $self = shift;
    return $self->{back_rect_height} // LEGEND_HEIGHT;
}

# Updates position of legend and value box
# when canvas is resized or scrolled
sub reposition {
    my $self = shift;
    my $width_px  = shift;
    my $height_px = shift;

    return if not defined $self->{legend};

    # Convert coordinates into world units
    # (this has been tricky to get working right...)
    my ($width, $height) = $self->{canvas}->c2w($width_px || 0, $height_px || 0);

    my ($scroll_x, $scroll_y) = $self->{canvas}->get_scroll_offsets();
       ($scroll_x, $scroll_y) = $self->{canvas}->c2w($scroll_x, $scroll_y);

    my ($border_width, $legend_width) = $self->{canvas}->c2w(BORDER_SIZE, $self->get_width);

    # Get the pixels per unit value from the canvas
    # to scale the legend with.
    my $ppu = $self->{canvas}->get_pixels_per_unit();

    # Reposition the legend group box
    $self->{legend_group}->set(
        x => $width  + $scroll_x - $legend_width,
        y => $scroll_y,
    );

    # Scale the legend's height and width to match the current size of the canvas. 
    my $matrix = [
        $legend_width * $ppu, # scale x
        0,
        0,
        $height / $self->{legend_height}, # scale y
        0,
        0
    ];
    $self->{legend_colours_group}->affine_absolute($matrix);

    # Reposition the "mark" textboxes
    my @mark_arr
        = $self->get_zscore_mode ? @{$self->{zscore_marks}}
        : $self->get_prank_mode  ? @{$self->{prank_marks}}
        : $self->get_canape_mode ? @{$self->{canape_marks}}
        : $self->get_divergent_mode ? @{$self->{divergent_marks}}
        : $self->get_ratio_mode  ? @{$self->{ratio_marks}}
        : @{$self->{marks}};
    foreach my $i (0..$#mark_arr) {
        my $mark = $mark_arr[$#mark_arr - $i];
        #  move the mark to right align with the legend
        my @bounds  = $mark->get_bounds;
        my @lbounds = $self->{legend}->get_bounds;
        my $offset  = $lbounds[0] - $bounds[2];
        $mark->move ($offset - ($width * MARK_X_LEGEND_OFFSET ), 0);

        # Set the location of the y of the marks
        # Has a vertical offset for the first and
        # last marks.
        my $y_offset = 0;
        if ($i == 0) {
            $y_offset =  MARK_Y_LEGEND_OFFSET;
        }
        elsif ($i == $#mark_arr) {
            $y_offset = -MARK_Y_LEGEND_OFFSET;
        }
        $mark_arr[$i]->set(
            y => $i * $height / $#mark_arr + $y_offset / $ppu,
        );

        $mark->raise_to_top;
        $mark->show;
    }

    # Reposition value box
    if ($self->{value_group}) {
        my ($value_x, $value_y) = $self->{value_group}->get('x', 'y');
        $self->{value_group}->move(
            $scroll_x - $value_x,
            $scroll_y - $value_y,
        );

        my ($text_width, $text_height)
            = $self->{value_text}->get('text-width', 'text-height');

        # Resize value background rectangle
        $self->{value_rect}->set(
            x2 => $text_width,
            y2 => $text_height,
        );
    }

    return;
}

# Set colouring mode - 'Hue' or 'Sat'
sub set_mode {
    my $self = shift;
    my $mode = shift;

    $mode = ucfirst lc $mode;

    croak "Invalid display mode '$mode'\n"
        if not $mode =~ /^Hue|Sat|Grey$/;

    $self->{legend_mode} = $mode;

    #$self->colour_cells();

    # Update legend
    if ($self->{legend}) { # && $self->{width_px} && $self->{height_px}) {
        $self->{legend} = $self->make_rect();
        $self->reposition($self->{width_px}, $self->{height_px});  #  trigger a redisplay of the legend
    }

    return;
}

sub get_mode {
    my $self = shift;
    return $self->{legend_mode} //= 'Hue';
}


=head2 setHue

Sets the hue for the saturation (constant-hue) colouring mode

=cut

sub set_hue {
    my $self = shift;
    my $rgb = shift;

    my @x = (rgb_to_hsv($rgb->red / 257, $rgb->green /257, $rgb->blue / 257));

    my $hue = (rgb_to_hsv($rgb->red / 257, $rgb->green /257, $rgb->blue / 257))[0];
    my $last_hue_used = $self->get_hue;
    return if defined $last_hue_used && $hue == $last_hue_used;

    $self->{hue} = $hue;

    # Update legend
    if ($self->{legend}) {
        $self->{legend} = $self->make_rect();
        $self->reposition($self->{width_px}, $self->{height_px})  #  trigger a redisplay of the legend
    }

    return;
}

sub get_hue {
    my $self = shift;
    return $self->{hue};
}

##########################################################
# Colouring based on an analysis value
##########################################################

sub get_colour_for_undef {
    my $self = shift;
    my $colour_none = shift;

    return $self->{colour_none} // $self->set_colour_for_undef ($colour_none);
}

sub set_colour_for_undef {
    my ($self, $colour) = @_;

    $colour //= COLOUR_WHITE;

    croak "Colour argument must be a Gtk2::Gdk::Color object\n"
      if not blessed ($colour) eq 'Gtk2::Gdk::Color';

    $self->{colour_none} = $colour;
}

my %colour_methods = (
    Hue  => 'get_colour_hue',
    Sat  => 'get_colour_saturation',
    Grey => 'get_colour_grey',
    #Canape => 'get_colour_canape',
);

sub get_colour {
    my ($self, $val, $min, $max) = @_;

    return $self->get_colour_canape ($val)
      if $self->get_canape_mode;

    my $method = $colour_methods{$self->{legend_mode}};

    croak "Unknown colour system: $self->{legend_mode}\n"
        if !$method;

    if (defined $min and $val < $min) {
        $val = $min;
    }
    if (defined $max and $val > $max) {
        $val = $max;
    }
    if ($self->get_log_mode) {
        if ($max != $min) {
            $val = log (1 + 100 * ($val - $min) / ($max - $min)) / log (101);
        }
        else {
            $val = 0;
        }
        $min = 0;
        $max = 1;
    }

    return $self->$method($val, $min, $max);
}


sub get_colour_canape {
    my ($self, $val) = @_;
    $val //= -1;  #  avoid undef key warnings
    return $canape_colour_hash{$val} || COLOUR_WHITE;
}

#  colours from https://colorbrewer2.org/#type=diverging&scheme=RdYlBu&n=7
#  refactor as state var inside sub when we require a perl version that
#  supports state on lists (5.28)
my @zscore_colours
    = map {Gtk2::Gdk::Color->parse($_)}
    reverse ('#d73027', '#fc8d59', '#fee090', '#ffffbf', '#e0f3f8', '#91bfdb', '#4575b4');

sub get_colour_zscore {
    my ($self, $val) = @_;

    state $default_colour = Gtk2::Gdk::Color->new(0, 0, 0);

    return $default_colour
        if not defined $val;

    #  returns -1 if not found, which will give us last item in @zscore_colours
    my $idx
        = firstidx {$val < 0 ? $val < $_ : $val <= $_}
          (-2.58, -1.96, -1.65, 1.65, 1.96, 2.58);

    if ($self->get_invert_colours) {
        $idx = $idx < 0 ? 0 : ($#zscore_colours - $idx);
    }

    return $zscore_colours[$idx];
}

#  same colours as the z-scores
sub get_colour_prank {
    my ($self, $val) = @_;

    state $default_colour = Gtk2::Gdk::Color->new(0, 0, 0);

    return $default_colour
        if not defined $val;

    #  returns -1 if not found, which will give us last item in @zscore_colours
    my $idx
        = firstidx {$val < 0 ? $val < $_ : $val <= $_}
          (0.01, 0.025, 0.05, 0.95, 0.975, 0.99);

    if ($self->get_invert_colours) {
        $idx = $idx < 0 ? 0 : ($#zscore_colours - $idx);
    }

    return $zscore_colours[$idx];
}

sub get_colour_divergent {
    my ($self, $val, $centre, $max_dist) = @_;

    state $default_colour = Gtk2::Gdk::Color->new(0, 0, 0);

    return $default_colour
        if ! defined $max_dist;

    state $centre_colour = Gtk2::Gdk::Color->parse('#ffffbf');

    $centre //= 0;

    return $centre_colour
        if $val == $centre || $max_dist == 0;

    my $colour;
    my @arr_cen = (0xff, 0xff, 0xbf);
    my @arr_hi  = (0x45, 0x75, 0xb4); # blue
    my @arr_lo  = (0xd7, 0x30, 0x27); # red

    if ($self->get_invert_colours) {
        @arr_lo  = (0x45, 0x75, 0xb4); # blue
        @arr_hi  = (0xd7, 0x30, 0x27); # red
    }

    $max_dist = abs $max_dist;
    my $pct = abs (($val - $centre) / $max_dist);

    if ($self->get_log_mode) {
        $pct = log (1 + 100 * $pct) / log (101);
    }

    #  handle out of range vals
    $pct = min (1, $pct);

    # interpolate between centre and extreme for each of R, G and B
    my @rgb
        = map {
        ($arr_cen[$_]
            + $pct
            * (($val < $centre ? $arr_hi[$_] : $arr_lo[$_]) - $arr_cen[$_])
        ) * 256} (0..2);

    $colour = Gtk2::Gdk::Color->new(@rgb);
    return $colour;
}

sub get_colour_ratio {
    my ($self, $val, $extreme) = @_;

    state $default_colour = Gtk2::Gdk::Color->new(0, 0, 0);

    return $default_colour
        if ! defined $extreme;

    state $centre_colour = Gtk2::Gdk::Color->parse('#ffffbf');

    return $centre_colour
        if $val == 1 || $extreme == 1;

    #  simplify logic below
    if ($extreme < 1) {
        $extreme = 1 / $extreme;
    }

    my @arr_cen = (0xff, 0xff, 0xbf);
    my @arr_hi  = (0x45, 0x75, 0xb4); # blue
    my @arr_lo  = (0xd7, 0x30, 0x27); # red

    if ($self->get_invert_colours) {
        @arr_lo  = (0x45, 0x75, 0xb4); # blue
        @arr_hi  = (0xd7, 0x30, 0x27); # red
    }

    #  ensure fractions get correct scaling
    my $scaled = $val < 1 ? 1 / $val : $val;

    my $pct = abs (($scaled - 1) / abs ($extreme - 1));
    $pct = min ($pct, 1);  #  account for bounded ranges

    if ($self->get_log_mode) {
        $pct = log (1 + 100 * $pct) / log (101);
    }

    # interpolate between centre and extreme for each of R, G and B
    my @rgb
        = map {
        ($arr_cen[$_]
            + $pct
            * (($val < 1 ? $arr_hi[$_] : $arr_lo[$_]) - $arr_cen[$_])
        ) * 256} (0..2);
# say "$val, $extreme, $scaled";
    return Gtk2::Gdk::Color->new(@rgb);
}

sub get_colour_hue {
    my ($self, $val, $min, $max) = @_;
    # We use the following system:
    #   Linear interpolation between min...max
    #   HUE goes from 180 to 0 as val goes from min to max
    #   Saturation, Brightness are 1
    #
    state $default_colour = Gtk2::Gdk::Color->new(0, 0, 0);
    my $hue;

    return $default_colour
      if ! defined $max || ! defined $min;

    if ($max != $min) {
        return $default_colour
          if ! defined $val;
        $hue = ($val - $min) / ($max - $min);
    }
    else {
        $hue = 0;
    }

    if ($self->get_invert_colours) {
        $hue = 1 - $hue;
    }

    $hue = 180 * min (1, max ($hue, 0));

    $hue = int(180 - $hue); # reverse 0..180 to 180..0 (this makes high values red)

    my ($r, $g, $b) = hsv_to_rgb($hue, 1, 1);

    return Gtk2::Gdk::Color->new($r*257, $g*257, $b*257);
}

sub get_colour_saturation {
    my ($self, $val, $min, $max) = @_;
    #   Linear interpolation between min...max
    #   SATURATION goes from 0 to 1 as val goes from min to max
    #   Hue is variable, Brightness 1
    state $default_colour = Gtk2::Gdk::Color->new(0, 0, 0);

    return $default_colour
      if ! defined $val || ! defined $max || ! defined $min;

    my $sat;
    if ($max != $min) {
        $sat = ($val - $min) / ($max - $min);
    }
    else {
        $sat = 1;
    }
    $sat = min (1, max ($sat, 0));

    if ($self->get_invert_colours) {
        $sat = 1 - $sat;
    }

    my ($r, $g, $b) = hsv_to_rgb($self->{hue}, $sat, 1);

    return Gtk2::Gdk::Color->new($r*257, $g*257, $b*257);
}

sub get_colour_grey {
    my ($self, $val, $min, $max) = @_;

    state $default_colour = Gtk2::Gdk::Color->new(0, 0, 0);

    return $default_colour
      if ! defined $val || ! defined $max || ! defined $min;

    my $sat;
    if ($max != $min) {
        $sat = ($val - $min) / ($max - $min);
    }
    else {
        $sat = 1;
    }

    if ($self->get_invert_colours) {
        $sat = 1 - $sat;
    }

    $sat *= 255;
    $sat = $self->rescale_grey($sat);  #  don't use all the shades
    $sat *= 257;

    return Gtk2::Gdk::Color->new($sat, $sat, $sat);
}


# FROM http://blog.webkist.com/archives/000052.html
# by Jacob Ehnmark
sub hsv_to_rgb {
    my($h, $s, $v) = @_;
    
    return if !defined $h;
    
    $v = $v >= 1.0 ? 255 : $v * 256;

    # Grey image.
    return((int($v)) x 3) if ($s == 0);

    $h /= 60;
    my $i = int($h);
    my $f = $h - int($i);
    my $p = int($v * (1 - $s));
    my $q = int($v * (1 - $s * $f));
    my $t = int($v * (1 - $s * (1 - $f)));
    $v = int($v);

    if   ($i == 0) { return($v, $t, $p); }
    elsif($i == 1) { return($q, $v, $p); }
    elsif($i == 2) { return($p, $v, $t); }
    elsif($i == 3) { return($p, $q, $v); }
    elsif($i == 4) { return($t, $p, $v); }
    else           { return($v, $p, $q); }
}

sub rgb_to_hsv {
    my $var_r = $_[0] / 255;
    my $var_g = $_[1] / 255;
    my $var_b = $_[2] / 255;
    my($var_min, $var_max) = minmax($var_r, $var_g, $var_b);
    my $del_max = $var_max - $var_min;

    if($del_max) {
        my $del_r = ((($var_max - $var_r) / 6) + ($del_max / 2)) / $del_max;
        my $del_g = ((($var_max - $var_g) / 6) + ($del_max / 2)) / $del_max;
        my $del_b = ((($var_max - $var_b) / 6) + ($del_max / 2)) / $del_max;
    
        my $h;
        if($var_r == $var_max) { $h = $del_b - $del_g; }
        elsif($var_g == $var_max) { $h = 1/3 + $del_r - $del_b; }
        elsif($var_b == $var_max) { $h = 2/3 + $del_g - $del_r; }
    
        if($h < 0) { $h += 1 }
        if($h > 1) { $h -= 1 }
    
        return($h * 360, $del_max / $var_max, $var_max);
    }
    else {
        return(0, 0, $var_max);
    }
}

# Sets the values of the textboxes next to the legend */
sub set_min_max {
    #  val1 and val2 could be min/max or mid/extent
    my ($self, $val1, $val2) = @_;

    return $self->set_text_marks_zscore
        if $self->get_zscore_mode;

    return $self->set_text_marks_prank
        if $self->get_prank_mode;

    # foreach my $mark (@{$self->{marks}}) {
    #     $mark->show;
    # }

    return $self->set_text_marks_canape
        if $self->get_canape_mode;

    return $self->set_text_marks_divergent ($val1, $val2)
        if $self->get_divergent_mode;

    return $self->set_text_marks_ratio ($val2)
        if $self->get_ratio_mode;

    my $min = $val1 //= $self->{last_min};
    my $max = $val2 //= $self->{last_max};

    $self->{last_min} = $min;
    $self->{last_max} = $max;


    return if ! ($self->{marks}
                 && defined $min
                 && defined $max
                );

    # Set legend textbox markers
    my @mark_arr = @{$self->{marks}};
    my $marker_step = ($max - $min) / $#mark_arr;
    foreach my $i (0..$#mark_arr) {
        my $val = $min + $i * $marker_step;
        if ($self->get_log_mode) {
            my $log_step = log (101) * $i / $#mark_arr;
            #  should use a method for each transform
            #  (log and antilog)
            #  orig:
            #  $val = log (1 + 100 * ($val - $min) / ($max - $min)) / log (101);
            $val = (exp ($log_step) - 1) / 100 * ($max - $min) + $min;
        }
        my $text = $self->format_number_for_display (number => $val);
        my $text_num = $text;  #  need to not have '<=' and '>=' in comparison lower down
        if ($i == 0 and $self->{legend_lt_flag}) {
            $text = '<=' . $text;
        }
        elsif ($i == $#mark_arr and $self->{legend_gt_flag}) {
            $text = '>=' . $text;
        }
        elsif ($self->{legend_lt_flag} or $self->{legend_gt_flag}) {
            $text = '  ' . $text;
        }

        my $mark = $self->{marks}[$#mark_arr - $i];
        $mark->set( text => $text );
        #  move the mark to right align with the legend
        my @bounds = $mark->get_bounds;
        my @lbounds = $self->{legend}->get_bounds;
        my $offset = $lbounds[0] - $bounds[2];
        if (($text_num + 0) != 0) {
            $mark->move ($offset - length ($text), 0);
        }
        else {
            $mark->move ($offset - length ($text) - 0.5, 0);
        }
        $mark->raise_to_top;
    }

    return;
}

sub set_text_marks_canape {
    my $self = shift;

    return if !$self->{marks};

    foreach my $mark (@{$self->{marks}}) {
        $mark->hide;
    }

    my @strings = qw /super mixed palaeo neo non-sig/;

    my $mark_arr = $self->{canape_marks} //= [];
    if (!@$mark_arr) {
        foreach my $i (0 .. $#strings) {
            my $anchor_loc = $i == 0 ? 'nw' : $i == $#strings ? 'sw' : 'w';
            $mark_arr->[$i] = $self->make_mark($anchor_loc);
        }
    }

    # Set legend textbox markers
    foreach my $i (0..$#strings) {
        my $mark = $mark_arr->[$#$mark_arr - $i];
        $mark->set( text => $strings[$i] );
        $mark->raise_to_top;
    }

    return;
}

sub set_text_marks_zscore {
    my $self = shift;

    #  needed?  seem to remember it avoids triggering marks if grid is not set up
    return if !$self->{marks};

    foreach my $mark (@{$self->{marks}}) {
        $mark->hide;
    }

    my @strings = ('<-2.58', '[-2.58,-1.96)', '[-1.96,-1.65)', '[-1.65,1.65]', '(1.65,1.96]', '(1.96,2.58]', '>2.58');

    my $mark_arr = $self->{zscore_marks} //= [];
    if (!@$mark_arr) {
        foreach my $i (0 .. $#strings) {
            my $anchor_loc = $i == 0 ? 'nw' : $i == $#strings ? 'sw' : 'w';
            $mark_arr->[$i] = $self->make_mark($anchor_loc);
        }
    }

    # Set legend textbox markers
    foreach my $i (0 .. $#strings) {
        my $mark = $mark_arr->[$#strings - $i];
        $mark->set( text => $strings[$i] );
        # $mark->show;
        $mark->raise_to_top;
    }

    return;
}

#  refactor needed
sub set_text_marks_divergent {
    my ($self, $mid, $extent) = @_;

    my $mid2 = ($mid + $extent) / 2;
    my @strings = (
        $mid - $extent,
        $mid - $extent / 2,
        $mid,
        $mid + $extent / 2,
        $mid + $extent
    );

    if ($self->get_log_mode) {
        my $pct = abs (($strings[-2] - $mid) / abs ($extent));
        $pct = log (1 + 100 * $pct) / log (101);
        # say "P2: $pct";
        $strings[-2] *= $pct;
        $pct = abs (($strings[1] - $mid) / abs ($extent));
        $pct = log (1 + 100 * $pct) / log (101);
        # say "P1: $pct";
        $strings[1] *= $pct;
    }

    @strings = map {0 + sprintf "%.4g", $_} @strings;

    if ($self->{legend_lt_flag}) {
        $strings[0] = "<=$strings[0]";
    }
    if ($self->{legend_gt_flag}) {
        $strings[-1] = ">=$strings[-1]";
    }
    # say join ' ', @strings;

    $self->set_text_marks_for_labels (\@strings, $self->{divergent_marks});
}

sub set_text_marks_ratio {
    my ($self, $max) = @_;

    $max //= 1;
    my $mid = 1 + ($max - 1) / 2;
    my @strings = (
        1 / $max,
        1 / $mid,
        1,
        $mid,
        $max
    );

    if ($self->get_log_mode) {
        my $pct = abs (($mid - 1) / abs ($max - 1));
        $pct = log (1 + 100 * $pct) / log (101);
        $strings[1]  = 1 / ($mid * $pct);
        $strings[-2] = $mid * $pct;
    }

    @strings = map {0 + sprintf "%.4g", $_} @strings;

    if ($self->{legend_lt_flag}) {
        $strings[0] = "<=$strings[0]";
    }
    if ($self->{legend_gt_flag}) {
        $strings[-1] = ">=$strings[-1]";
    }

    $self->set_text_marks_for_labels (\@strings, $self->{ratio_marks});
}

sub set_text_marks_prank {
    my $self = shift;
    my @strings = ('<0.01', '<0.025', '<0.05', '[0.05,0.95]', '>0.95', '>0.975', '>0.99');
    $self->set_text_marks_for_labels (\@strings, $self->{prank_marks});
}

#  generalises z-score version - need to simplify it
sub set_text_marks_for_labels {
    my ($self, \@strings, $mark_arr) = @_;

    #  needed?  seem to remember it avoids triggering marks if grid is not set up
    return if !$self->{marks};

    $mark_arr //= [];

    carp "Mark count does not match label count"
        if scalar(@strings) != scalar @$mark_arr;

    foreach my $mark (@{$self->{marks}}) {
        $mark->hide;
    }

    if (!@$mark_arr) {
        foreach my $i (0 .. $#strings) {
            my $anchor_loc = $i == 0 ? 'nw' : $i == $#strings ? 'sw' : 'w';
            $mark_arr->[$i] = $self->make_mark($anchor_loc);
        }
    }

    # Set legend textbox markers
    foreach my $i (0 .. $#strings) {
        my $mark = $mark_arr->[$#strings - $i];
        $mark->set( text => $strings[$i] );
        # $mark->show;
        $mark->raise_to_top;
    }

    return;
}


sub set_log_mode_on {
    my ($self) = @_;
    return $self->{log_mode} = 1;
}

sub set_log_mode_off {
    my ($self) = @_;
    return $self->{log_mode} = 0;
}

sub get_log_mode {
    $_[0]->{log_mode};
}

sub set_canape_mode_on {
    my ($self) = @_;
    my $prev_val = $self->{canape_mode};
    $self->{canape_mode} = 1;
    if (!$prev_val) {  #  update legend colours
        $self->make_rect;
        $self->reposition($self->{width_px}, $self->{height_px})  #  trigger a redisplay of the legend
    }
    return 1;
}

sub set_canape_mode_off {
    my ($self) = @_;
    my $prev_val = $self->{canape_mode};
    $self->{canape_mode} = 0;
    foreach my $mark (@{$self->{canape_marks}}) {
        $mark->hide;
    }
    if ($prev_val) {  #  give back our colours
        $self->make_rect;
        $self->reposition($self->{width_px}, $self->{height_px})  #  trigger a redisplay of the legend
    }
    return 0;
}

sub get_canape_mode {
    $_[0]->{canape_mode};
}

sub set_canape_mode {
    my ($self, $bool) = @_;
    if ($bool) {
        $self->set_canape_mode_on;
    }
    else {
        $self->set_canape_mode_off;
    }
    return $self->{canape_mode};
}

sub set_zscore_mode_on {
    my ($self) = @_;
    my $prev_val = $self->{zscore_mode};
    $self->{zscore_mode} = 1;
    if (!$prev_val) {  #  update legend colours
        $self->make_rect;
        $self->reposition($self->{width_px}, $self->{height_px});  #  trigger a redisplay of the legend
    }
    return 1;
}

sub set_zscore_mode_off {
    my ($self) = @_;
    my $prev_val = $self->{zscore_mode};
    $self->{zscore_mode} = 0;
    foreach my $mark (@{$self->{zscore_marks}}) {
        $mark->hide;
    }
    if ($prev_val) {  #  give back our colours
        $self->make_rect;
        $self->reposition($self->{width_px}, $self->{height_px})  #  trigger a redisplay of the legend
    }
    return 0;
}

sub get_zscore_mode {
    $_[0]->{zscore_mode};
}

sub set_zscore_mode {
    my ($self, $bool) = @_;
    if ($bool) {
        $self->set_zscore_mode_on;
    }
    else {
        $self->set_zscore_mode_off;
    }
    return $self->{zscore_mode};
}

sub set_divergent_mode_on {
    my ($self) = @_;
    my $prev_val = $self->{divergent_mode};
    $self->{divergent_mode} = 1;
    if (!$prev_val) {  #  update legend colours
        $self->make_rect;
        $self->reposition($self->{width_px}, $self->{height_px});  #  trigger a redisplay of the legend
    }
    return 1;
}

sub set_divergent_mode_off {
    my ($self) = @_;
    my $prev_val = $self->{divergent_mode};
    $self->{divergent_mode} = 0;
    foreach my $mark (@{$self->{divergent_marks}}) {
        $mark->hide;
    }
    if ($prev_val) {  #  give back our colours
        $self->make_rect;
        $self->reposition($self->{width_px}, $self->{height_px})  #  trigger a redisplay of the legend
    }
    return 0;
}

sub get_divergent_mode {
    $_[0]->{divergent_mode};
}

sub set_divergent_mode {
    my ($self, $bool) = @_;
    if ($bool) {
        $self->set_divergent_mode_on;
    }
    else {
        $self->set_divergent_mode_off;
    }
    return $self->{divergent_mode};
}

sub set_ratio_mode_on {
    my ($self) = @_;
    my $prev_val = $self->{ratio_mode};
    $self->{ratio_mode} = 1;
    if (!$prev_val) {  #  update legend colours
        $self->make_rect;
        $self->reposition($self->{width_px}, $self->{height_px});  #  trigger a redisplay of the legend
    }
    return 1;
}

sub set_ratio_mode_off {
    my ($self) = @_;
    my $prev_val = $self->{ratio_mode};
    $self->{ratio_mode} = 0;
    foreach my $mark (@{$self->{ratio_marks}}) {
        $mark->hide;
    }
    if ($prev_val) {  #  give back our colours
        $self->make_rect;
        $self->reposition($self->{width_px}, $self->{height_px})  #  trigger a redisplay of the legend
    }
    return 0;
}

sub get_ratio_mode {
    $_[0]->{ratio_mode};
}

sub set_ratio_mode {
    my ($self, $bool) = @_;
    if ($bool) {
        $self->set_ratio_mode_on;
    }
    else {
        $self->set_ratio_mode_off;
    }
    return $self->{ratio_mode};
}

sub set_prank_mode_on {
    my ($self) = @_;
    my $prev_val = $self->{prank_mode};
    $self->{prank_mode} = 1;
    if (!$prev_val) {  #  update legend colours
        $self->make_rect;
        $self->reposition($self->{width_px}, $self->{height_px});  #  trigger a redisplay of the legend
    }
    return 1;
}

sub set_prank_mode_off {
    my ($self) = @_;
    my $prev_val = $self->{prank_mode};
    $self->{prank_mode} = 0;
    foreach my $mark (@{$self->{prank_marks}}) {
        $mark->hide;
    }
    if ($prev_val) {  #  give back our colours
        $self->make_rect;
        $self->reposition($self->{width_px}, $self->{height_px})  #  trigger a redisplay of the legend
    }
    return 0;
}

sub get_prank_mode {
    $_[0]->{prank_mode};
}

sub set_prank_mode {
    my ($self, $bool) = @_;
    if ($bool) {
        $self->set_prank_mode_on;
    }
    else {
        $self->set_prank_mode_off;
    }
    return $self->{prank_mode};
}



#  dup from Tab.pm - need to inherit from single source
sub format_number_for_display {
    my $self = shift;
    my %args = @_;
    my $val = $args{number};

    my $text = sprintf ('%.4f', $val); # round to 4 d.p.
    if ($text == 0) {
        $text = sprintf ('%.2e', $val);
    }
    if ($text == 0) {
        $text = 0;  #  make sure it is 0 and not 0.00e+000
    };
    return $text;
}

#  rescale the grey values into lighter shades
sub rescale_grey {
    my $self  = shift;
    my $value = shift;
    my $max   = shift // 255;

    $value /= $max;
    $value *= (LIGHTEST_GREY_FRAC - DARKEST_GREY_FRAC);
    $value += DARKEST_GREY_FRAC;
    $value *= $max;

    return $value;
}

#  flip the colour ranges if true
sub get_invert_colours {
    $_[0]->{invert_colours};
};

sub set_invert_colours {
    my ($self, $bool) = @_;
    $self->{invert_colours} = !!$bool;
}

1;
