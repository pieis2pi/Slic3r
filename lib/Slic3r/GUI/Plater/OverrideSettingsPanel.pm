# Maintains, displays, adds and removes overrides of slicing parameters.

package Slic3r::GUI::Plater::OverrideSettingsPanel;
use strict;
use warnings;
use utf8;

use List::Util qw(first);
use Wx qw(:misc :sizer :button wxTAB_TRAVERSAL wxSUNKEN_BORDER wxBITMAP_TYPE_PNG
    wxTheApp);
use Wx::Event qw(EVT_BUTTON EVT_LEFT_DOWN EVT_MENU);
use base 'Wx::ScrolledWindow';

use constant ICON_MATERIAL      => 0;
use constant ICON_SOLIDMESH     => 1;
use constant ICON_MODIFIERMESH  => 2;

my %icons = (
    'Advanced'              => 'wand.png',
    'Extruders'             => 'funnel.png',
    'Extrusion Width'       => 'funnel.png',
    'Infill'                => 'infill.png',
    'Layers and Perimeters' => 'layers.png',
    'Skirt and brim'        => 'box.png',
    'Speed'                 => 'time.png',
    'Speed > Acceleration'  => 'time.png',
    'Support material'      => 'building.png',
);

sub new {
    my $class = shift;
    my ($parent, %params) = @_;
    my $self = $class->SUPER::new($parent, -1, wxDefaultPosition, $params{size} // wxDefaultSize, wxTAB_TRAVERSAL);
    $self->{default_config} = Slic3r::Config->new;
    $self->{config} = Slic3r::Config->new;
    $self->{on_change} = $params{on_change};
    $self->{editable} = 1;
    $self->{fixed_options} = {};
    
    $self->{sizer} = Wx::BoxSizer->new(wxVERTICAL);
    
    $self->{options_sizer} = Wx::BoxSizer->new(wxVERTICAL);
    $self->{sizer}->Add($self->{options_sizer}, 0, wxEXPAND | wxALL, 0);
    
    # option selector
    {
        # create the button
        my $btn = $self->{btn_add} = Wx::BitmapButton->new($self, -1, Wx::Bitmap->new($Slic3r::var->("add.png"), wxBITMAP_TYPE_PNG),
            wxDefaultPosition, wxDefaultSize, Wx::wxBORDER_NONE);
        $btn->SetToolTipString("Override one more option")
            if $btn->can('SetToolTipString');
        EVT_LEFT_DOWN($btn, sub {
            my $menu = Wx::Menu->new;
            my $last_cat = '';
            foreach my $opt_key (@{$self->{options}}) {
                my $id = &Wx::NewId();
                
                # add icon, if we have one for this category
                my $icon;
                if (my $cat = $Slic3r::Config::Options->{$opt_key}{category}) {
                    if ($last_cat && $cat ne $last_cat) {
                        $menu->AppendSeparator;
                    }
                    $last_cat = $cat;
                    $icon = $icons{$cat};
                }
                
                my $menuItem = $menu->Append($id, $self->{option_labels}{$opt_key});
                wxTheApp->set_menu_item_icon($menuItem, $icon) if $icon;
                
                EVT_MENU($menu, $id, sub {
                    $self->{config}->set($opt_key, $self->{default_config}->get($opt_key));
                    $self->update_optgroup;
                    $self->{on_change}->($opt_key) if $self->{on_change};
                });
            }
            $self->PopupMenu($menu, $btn->GetPosition);
            $menu->Destroy;
        });
        
        my $h_sizer = Wx::BoxSizer->new(wxHORIZONTAL);
        $h_sizer->Add($btn, 0, wxALL, 0);
        $self->{sizer}->Add($h_sizer, 0, wxEXPAND | wxBOTTOM, 10);
    }
    
    $self->SetSizer($self->{sizer});
    $self->SetScrollbars(0, 1, 0, 1);
    
    $self->set_opt_keys($params{opt_keys}) if $params{opt_keys};
    $self->update_optgroup;
    
    return $self;
}

# Sets the config used to get the default values for user-added options.
sub set_default_config {
    my ($self, $config) = @_;
    $self->{default_config} = $config;
}

# Sets the target config, whose options will be displayed in the OptionsGroup.
sub set_config {
    my ($self, $config) = @_;
    $self->{config} = $config;
    $self->update_optgroup;
}

# Sets the options listed in the Add button.
sub set_opt_keys {
    my ($self, $opt_keys) = @_;
    
    # sort options by category+label
    $self->{option_labels} = {};
    foreach my $opt_key (@$opt_keys) {
        my $def = $Slic3r::Config::Options->{$opt_key} or next;
        if (!$def->{category}) {
            #printf "Skipping %s\n", $opt_key;
            next;
        }
        $self->{option_labels}{$opt_key} = sprintf '%s > %s',
            $def->{category},
            $def->{full_label} // $def->{label};
    };
    $self->{options} = [ sort { $self->{option_labels}{$a} cmp $self->{option_labels}{$b} } keys %{$self->{option_labels}} ];
}

# Sets the options that user can't remove.
sub set_fixed_options {
    my ($self, $opt_keys) = @_;
    $self->{fixed_options} = { map {$_ => 1} @$opt_keys };
    $self->update_optgroup;
}

sub fixed_options {
    my ($self) = @_;
    
    return keys %{$self->{fixed_options}};
}

sub update_optgroup {
    my $self = shift;
    
    $self->{options_sizer}->Clear(1);
    return if !defined $self->{config};
    
    $self->{btn_add}->Show($self->{editable});
    
    my %categories = ();
    foreach my $opt_key (@{$self->{config}->get_keys}) {
        my $category = $Slic3r::Config::Options->{$opt_key}{category};
        $categories{$category} ||= [];
        push @{$categories{$category}}, $opt_key;
    }
    foreach my $category (sort keys %categories) {
        my $optgroup;
        $optgroup = Slic3r::GUI::ConfigOptionsGroup->new(
            parent          => $self,
            title           => $category,
            config          => $self->{config},
            full_labels     => 1,
            label_font      => $Slic3r::GUI::small_font,
            sidetext_font   => $Slic3r::GUI::small_font,
            label_width     => 120,
            on_change       => sub {
                my ($opt_key) = @_;
                $self->{on_change}->($opt_key) if $self->{on_change};
            },
            extra_column    => sub {
                my ($line) = @_;
                
                my $opt_id = $line->get_options->[0]->opt_id;  # we assume that we have one option per line
                my ($opt_key, $opt_index) = @{ $optgroup->_opt_map->{$opt_id} };
                
                # disallow deleting fixed options
                return undef if $self->{fixed_options}{$opt_key} || !$self->{editable};
                
                my $btn = Wx::BitmapButton->new($self, -1, Wx::Bitmap->new($Slic3r::var->("delete.png"), wxBITMAP_TYPE_PNG),
                    wxDefaultPosition, wxDefaultSize, Wx::wxBORDER_NONE);
                EVT_BUTTON($self, $btn, sub {
                    $self->{config}->erase($opt_key);
                    $self->{on_change}->($opt_key) if $self->{on_change};
                    wxTheApp->CallAfter(sub { $self->update_optgroup });
                });
                return $btn;
            },
        );
        foreach my $opt_key (sort @{$categories{$category}}) {
            # For array options we override the first value.
            my $opt_index = (ref($self->{config}->get($opt_key)) eq 'ARRAY') ? 0 : -1;
            $optgroup->append_single_option_line($opt_key, $opt_index);
        }
        $self->{options_sizer}->Add($optgroup->sizer, 0, wxEXPAND | wxBOTTOM, 0);
    }
    $self->GetParent->Layout;  # we need this for showing scrollbars
}

# work around a wxMAC bug causing controls not being disabled when calling Disable() on a Window
sub enable {
    my ($self) = @_;
    
    $self->{btn_add}->Enable;
    $self->Enable;
}

sub disable {
    my ($self) = @_;
    
    $self->{btn_add}->Disable;
    $self->Disable;
}

# Shows or hides the Add button.
sub set_editable {
    my ($self, $editable) = @_;
    
    $self->{editable} = $editable;
}

1;
