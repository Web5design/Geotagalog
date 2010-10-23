#------------------------------------------------------------------------------
# File:         H264.pm
#
# Description:  Read meta information from H.264 video
#
# Revisions:    2010/01/31 - P. Harvey Created
#
# References:   1) http://www.itu.int/rec/T-REC-H.264/e (T-REC-H.264-200305-S!!PDF-E.pdf)
#               2) http://miffteevee.co.uk/documentation/development/H264Parser_8cpp-source.html
#               3) http://ffmpeg.org/
#               4) US Patent 2009/0052875 A1
#               5) European Patent (EP2 051 528A1) application no. 07792522.0 filed 08.08.2007
#
# Glossary:     RBSP = Raw Byte Sequence Payload
#------------------------------------------------------------------------------

package Image::ExifTool::H264;

use strict;
use vars qw($VERSION);
use Image::ExifTool qw(:DataAccess :Utils);
use Image::ExifTool::Exif;

$VERSION = '1.00';

sub ProcessSEI($$);

my $parsePictureTiming; # flag to enable parsing of picture timing information (test only)

# information extracted from H.264 video streams
%Image::ExifTool::H264::Main = (
    GROUPS => { 2 => 'Video' },
    VARS => { NO_ID => 1 },
    NOTES => 'Tags extracted from H.264 video streams.',
    ImageWidth => { },
    ImageHeight => { },
    MDPM => { SubDirectory => { TagTable => 'Image::ExifTool::H264::MDPM' } },
);

# H.264 Supplemental Enhancement Information User Data (ref PH/4)
%Image::ExifTool::H264::MDPM = (
    GROUPS => { 2 => 'Location' },
    PROCESS_PROC => \&ProcessSEI,
    NOTES => q{
        The following tags are decoded from the Modified Digital Video Pack Metadata
        (MDPM) of the unregistered user data with UUID
        17ee8c60f84d11d98cd60800200c9a66 in the H.264 Supplemental Enhancement
        Information (SEI).  [Yes, this description is confusing, but nothing
        compared to the challenge of actually decoding the data!]  This information
        may exist at regular intervals through the entire video, but only the first
        occurrence is extracted unless the ExtractEmbedded option is used (in which
        case subsequent occurrences are extracted as sub-documents).
    },
    # 0x13 - TimeCode
    # 0x14 - BinaryGrup
    0x18 => {
        Name => 'DateTimeOriginal',
        Description => 'Date/Time Original',
        Groups => { 2 => 'Time' },
        Notes => 'combined with tag 0x19',
        Combine => 1,   # the next tag (0x19) contains the rest of the date
        # first byte is timezone information:
        #   0x80 - unused
        #   0x40 - DST flag (not currently decoded)
        #   0x20 - TimeZoneSign
        #   0x1e - TimeZoneValue
        #   0x01 - half-hour flag
        ValueConv => q{
            my ($tz, @a) = unpack('C*',$val);
            return sprintf('%.2x%.2x:%.2x:%.2x %.2x:%.2x:%.2x%s%.2d:%s', @a,
                           $tz & 0x20 ? '-' : '+', ($tz >> 1) & 0x0f,
                           $tz & 0x01 ? '30' : '00');
        },
        PrintConv => '$self->ConvertDateTime($val)',
    },
    0x70 => { # ConsumerCamera1
        Name => 'Camera1',
        SubDirectory => { TagTable => 'Image::ExifTool::H264::Camera1' },
    },
    0x71 => { # ConsumerCamera2
        Name => 'Camera2',
        SubDirectory => { TagTable => 'Image::ExifTool::H264::Camera2' },
    },
    # 0x73 Lens - val: 0x75ffffd3,0x0effffd3,0x59ffffd3,0x79ffffd3,0xffffffd3...
    # 0x74 Gain
    # 0x75 Pedestal
    # 0x76 Gamma
    # 0x77 Detail
    # 0x7b CameraPreset
    # 0x7c Flare
    # 0x7d Shading
    # 0x7e Knee
    0x7f => { # Shutter
        Name => 'Shutter',
        SubDirectory => { TagTable => 'Image::ExifTool::H264::Shutter' },
    },
    0xa0 => {
        Name => 'ExposureTime',
        Format => 'rational32u',
        Groups => { 2 => 'Camera' },
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
    },
    0xa1 => {
        Name => 'FNumber',
        Format => 'rational32u',
        Groups => { 2 => 'Camera' },
    },
    0xa2 => {
        Name => 'ExposureProgram',
        Format => 'int32u', # (guess)
        Groups => { 2 => 'Camera' },
        PrintConv => {
            0 => 'Not Defined',
            1 => 'Manual',
            2 => 'Program AE',
            3 => 'Aperture-priority AE',
            4 => 'Shutter speed priority AE',
            5 => 'Creative (Slow speed)',
            6 => 'Action (High speed)',
            7 => 'Portrait',
            8 => 'Landscape',
        },
    },
    0xa3 => {
        Name => 'BrightnessValue',
        Format => 'rational32s',
        Groups => { 2 => 'Image' },
    },
    0xa4 => {
        Name => 'ExposureCompensation',
        Format => 'rational32s',
        Groups => { 2 => 'Image' },
        PrintConv => 'Image::ExifTool::Exif::ConvertFraction($val)',
    },
    0xa5 => {
        Name => 'MaxApertureValue',
        Format => 'rational32u',
        Groups => { 2 => 'Camera' },
        ValueConv => '2 ** ($val / 2)',
        PrintConv => 'sprintf("%.1f",$val)',
    },
    0xa6 => {
        Name => 'Flash',
        Format => 'int32u', # (guess)
        Groups => { 2 => 'Camera' },
        Flags => 'PrintHex',
        SeparateTable => 'EXIF Flash',
        PrintConv =>  \%Image::ExifTool::Exif::flash,
    },
    0xa7 => {
        Name => 'CustomRendered',
        Format => 'int32u', # (guess)
        Groups => { 2 => 'Image' },
        PrintConv => {
            0 => 'Normal',
            1 => 'Custom',
        },
    },
    0xa8 => {
        Name => 'WhiteBalance',
        Format => 'int32u', # (guess)
        Groups => { 2 => 'Camera' },
        Priority => 0,
        PrintConv => {
            0 => 'Auto',
            1 => 'Manual',
        },
    },
    0xa9 => {
        Name => 'FocalLengthIn35mmFormat',
        Format => 'rational32u',
        Groups => { 2 => 'Camera' },
        PrintConv => '"$val mm"',
    },
    0xaa => {
        Name => 'SceneCaptureType',
        Format => 'int32u', # (guess)
        Groups => { 2 => 'Camera' },
        PrintConv => {
            0 => 'Standard',
            1 => 'Landscape',
            2 => 'Portrait',
            3 => 'Night',
        },
    },
    # 0xab-0xaf ExifOption
    0xb0 => {
        Name => 'GPSVersionID',
        Format => 'int8u',
        Count => 4,
        PrintConv => '$val =~ tr/ /./; $val',
    },
    0xb1 => {
        Name => 'GPSLatitudeRef',
        Format => 'string',
        PrintConv => {
            N => 'North',
            S => 'South',
        },
    },
    0xb2 => {
        Name => 'GPSLatitude',
        Format => 'rational32u',
        Notes => 'combined with tags 0xb3 and 0xb4',
        Combine => 2,   # combine the next 2 tags (0xb2=deg, 0xb3=min, 0xb4=sec)
        ValueConv => 'Image::ExifTool::GPS::ToDegrees($val)',
        PrintConv => 'Image::ExifTool::GPS::ToDMS($self, $val, 1)',
    },
    0xb5 => {
        Name => 'GPSLongitudeRef',
        Format => 'string',
        PrintConv => {
            E => 'East',
            W => 'West',
        },
    },
    0xb6 => {
        Name => 'GPSLongitude',
        Format => 'rational32u',
        Combine => 2,   # combine the next 2 tags (0xb6=deg, 0xb7=min, 0xb8=sec)
        Notes => 'combined with tags 0xb7 and 0xb8',
        ValueConv => 'Image::ExifTool::GPS::ToDegrees($val)',
        PrintConv => 'Image::ExifTool::GPS::ToDMS($self, $val, 1)',
    },
    0xb9 => {
        Name => 'GPSAltitudeRef',
        Format => 'int32u', # (guess)
        ValueConv => '$val ? 1 : 0', # because I'm not sure about the Format
        PrintConv => {
            0 => 'Above Sea Level',
            1 => 'Below Sea Level',
        },
    },
    0xba => { Name => 'GPSAltitude', Format => 'rational32u' },
    0xbb => {
        Name => 'GPSTimeStamp',
        Format => 'rational32u',
        Combine => 2,    # the next tags (0xbc/0xbd) contain the minutes/seconds
        Notes => 'combined with tags 0xbc and 0xbd',
        ValueConv => 'Image::ExifTool::GPS::ConvertTimeStamp($val)',
    },
    0xbe => {
        Name => 'GPSStatus',
        Format => 'string',
        PrintConv => {
            A => 'Measurement Active',
            V => 'Measurement Void',
        },
    },
    0xbf => {
        Name => 'GPSMeasureMode',
        Format => 'string',
        PrintConv => {
            2 => '2-Dimensional Measurement',
            3 => '3-Dimensional Measurement',
        },
    },
    0xc0 => {
        Name => 'GPSDOP',
        Description => 'GPS Dilution Of Precision',
        Format => 'rational32u',
    },
    0xc1 => {
        Name => 'GPSSpeedRef',
        Format => 'string',
        PrintConv => {
            K => 'km/h',
            M => 'mph',
            N => 'knots',
        },
    },
    0xc2 => { Name => 'GPSSpeed', Format => 'rational32u' },
    0xc3 => {
        Name => 'GPSTrackRef',
        Format => 'string',
        PrintConv => {
            M => 'Magnetic North',
            T => 'True North',
        },
    },
    0xc4 => { Name => 'GPSTrack', Format => 'rational32u' },
    0xc5 => {
        Name => 'GPSImgDirectionRef',
        Format => 'string',
        PrintConv => {
            M => 'Magnetic North',
            T => 'True North',
        },
    },
    0xc6 => { Name => 'GPSImgDirection', Format => 'rational32u' },
    0xc7 => {
        Name => 'GPSMapDatum',
        Format => 'string',
        Combine => 1,    # the next tag (0xc8) contains the rest of the string
        Notes => 'combined with tag 0xc8',
    },
    # 0xc9-0xcf - GPSOption
    0xe0 => {
        Name => 'MakeModel',
        SubDirectory => { TagTable => 'Image::ExifTool::H264::MakeModel' },
    },
    # 0xe1-0xef - MakerOption
    # 0xe1 - val: 0x01000670,0x01000678,0x06ffffff,0x01ffffff,0x01000020,0x01000400...
    # 0xe2-0xe8 - val: 0x00000000
);

# ConsumerCamera1 information (ref PH)
%Image::ExifTool::H264::Camera1 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 2 => 'Camera' },
    TAG_PREFIX => 'Camera1',
    PRINT_CONV => 'sprintf("0x%.2x",$val)',
    FIRST_ENTRY => 0,
    0 => {
        Name => 'ApertureSetting',
        PrintConv => {
            0xff => 'Auto',
            0xfe => 'Closed',
            OTHER => sub { sprintf('%.1f', 2 ** (($_[0] & 0x3f) / 8)) },
        },
    },
    1.1 => {
        Name => 'Gain',
        Mask => 0x0f,
        ValueConv => '($val - 1) * 3',
        PrintConv => '"$val dB"',
    },
    1.2 => {
        Name => 'ExposureProgram',
        Mask => 0xf0,
        ValueConv => '$val == 0xf0 ? undef : $val',
        PrintConv => {
            0x00 => 'Program AE',
            0x10 => 'Gain', #?
            0x20 => 'Shutter speed priority AE',
            0x30 => 'Aperture-priority AE',
            0x40 => 'Manual',
        },
    },
    2.1 => {
        Name => 'WhiteBalance',
        Mask => 0xe0,
        ValueConv => '$val == 0xe0 ? undef : $val',
        PrintConv => {
            0x00 => 'Auto',
            0x20 => 'Hold',
            0x40 => '1-Push',
            0x60 => 'Daylight',
        },
    },
    3 => {
        Name => 'Focus',
        ValueConv => '$val == 0xff ? undef : $val',
        PrintConv => q{
            my $foc = ($val & 0x7e) / (($val & 0x01) ? 40 : 400);
            return ($val & 0x80 ? 'Manual' : 'Auto') . " ($foc)";
        },
    },
);

# ConsumerCamera2 information (ref PH)
%Image::ExifTool::H264::Camera2 = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 2 => 'Camera' },
    TAG_PREFIX => 'Camera2',
    PRINT_CONV => 'sprintf("0x%.2x",$val)',
    FIRST_ENTRY => 0,
    1 => {
        Name => 'ImageStabilization',
        # no stabilization feature if whole byte is 0xff
        ValueConv => '$val == 0xff ? 0 : $val & 0x10',
        PrintConv => {
            0x00 => 'Off',
            0x10 => 'On',
        },
    },
);

# camera info 0x7f (ref PH)
%Image::ExifTool::H264::Shutter = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 2 => 'Camera' },
    TAG_PREFIX => 'Shutter',
    PRINT_CONV => 'sprintf("0x%.2x",$val)',
    FIRST_ENTRY => 0,
  # this worked for the HDR-CX500, but not for other models
  # --> more work is needed to decode this
  #  2.1 => {
  #      Name => 'ExposureTime',
  #      Mask => 0xf0,
  #      RawConv => '$val == 0xf0 ? undef : $val',
  #      ValueConv => '$val / 32000',
  #      PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
  #  },
);

# camera info 0xe0 (ref PH)
%Image::ExifTool::H264::MakeModel = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 2 => 'Camera' },
    FORMAT => 'int16u',
    0 => {
        Name => 'Make',
        PrintHex => 1,
        PrintConv => {
            0x0108 => 'Sony',
            0x1011 => 'Canon',
        },
    },
    # 1 => ModelIDCode according to ref 4/5 (I think not)
    # vals: 0x3001 - Sony HDR-CX105E/TG3E/XR500V
    #       0x1000 - Sony HDR-UX1
    #       0x3000 - Canon HF100 (30p)
    #       0x2000 - Canon HF100 (60i)
);

#==============================================================================
# Bitstream functions (used for H264 video)
#
# Member variables:
#   Mask    = mask for next bit to read (0 when all data has been read)
#   Pos     = byte offset of next word to read
#   Word    = current data word
#   Len     = total data length in bytes
#   DataPt  = data pointer
#..............................................................................

#------------------------------------------------------------------------------
# Read next word from bitstream
# Inputs: 0) BitStream ref
# Returns: true if there is more data (and updates
#          Mask, Pos and Word for first bit in next word)
sub ReadNextWord($)
{
    my $bstr = shift;
    my $pos = $$bstr{Pos};
    if ($pos + 4 <= $$bstr{Len}) {
        $$bstr{Word} = unpack("x$pos N", ${$$bstr{DataPt}});
        $$bstr{Mask} = 0x80000000;
        $$bstr{Pos} += 4;
    } elsif ($pos < $$bstr{Len}) {
        my @bytes = unpack("x$pos C*", ${$$bstr{DataPt}});
        my ($word, $mask) = (shift(@bytes), 0x80);
        while (@bytes) {
            $word = ($word << 8) | shift(@bytes);
            $mask <<= 8;
        }
        $$bstr{Word} = $word;
        $$bstr{Mask} = $mask;
        $$bstr{Pos} = $$bstr{Len};
    } else {
        return 0;
    }
    return 1;
}

#------------------------------------------------------------------------------
# Create a new BitStream object
# Inputs: 0) data ref
# Returns: BitStream ref, or null if data is empty
sub NewBitStream($)
{
    my $dataPt = shift;
    my $bstr = {
        DataPt => $dataPt,
        Len    => length($$dataPt),
        Pos    => 0,
        Mask   => 0,
    };
    ReadNextWord($bstr) or undef $bstr;
    return $bstr;
}

#------------------------------------------------------------------------------
# Get number of bits remaining in bit stream
# Inputs: 0) BitStream ref
# Returns: number of bits remaining
sub BitsLeft($)
{
    my $bstr = shift;
    my $bits = 0;
    my $mask = $$bstr{Mask};
    while ($mask) {
        ++$bits;
        $mask >>= 1;
    }
    return $bits + 8 * ($$bstr{Len} - $$bstr{Pos});
}

#------------------------------------------------------------------------------
# Get integer from bitstream
# Inputs: 0) BitStream ref, 1) number of bits
# Returns: integer (and increments position in bitstream)
sub GetIntN($$)
{
    my ($bstr, $bits) = @_;
    my $val = 0;
    while ($bits--) {
        $val <<= 1;
        ++$val if $$bstr{Mask} & $$bstr{Word};
        $$bstr{Mask} >>= 1 and next;
        ReadNextWord($bstr) or last;
    }
    return $val;
}

#------------------------------------------------------------------------------
# Get Exp-Golomb integer from bitstream
# Inputs: 0) BitStream ref
# Returns: integer (and increments position in bitstream)
sub GetGolomb($)
{
    my $bstr = shift;
    # first, count the number of zero bits to get the integer bit width
    my $count = 0;
    until ($$bstr{Mask} & $$bstr{Word}) {
        ++$count;
        $$bstr{Mask} >>= 1 and next;
        ReadNextWord($bstr) or last;
    }
    # then return the adjusted integer
    return GetIntN($bstr, $count + 1) - 1;
}

#------------------------------------------------------------------------------
# Get signed Exp-Golomb integer from bitstream
# Inputs: 0) BitStream ref
# Returns: integer (and increments position in bitstream)
sub GetGolombS($)
{
    my $bstr = shift;
    my $val = GetGolomb($bstr) + 1;
    return ($val & 1) ? -($val >> 1) : ($val >> 1);
}

# end bitstream functions
#==============================================================================

#------------------------------------------------------------------------------
# Decode H.264 scaling matrices
# Inputs: 0) BitStream ref
# Reference: http://ffmpeg.org/
sub DecodeScalingMatrices($)
{
    my $bstr = shift;
    if (GetIntN($bstr, 1)) {
        my ($i, $j);
        for ($i=0; $i<8; ++$i) {
            my $size = $i<6 ? 16 : 64;
            next unless GetIntN($bstr, 1);
            my ($last, $next) = (8, 8);
            for ($j=0; $j<$size; ++$j) {
                $next = ($last + GetGolombS($bstr)) & 0xff if $next;
                last unless $j or $next;
            }
        }
    }
}

#------------------------------------------------------------------------------
# Parse H.264 sequence parameter set RBSP (ref 1)
# Inputs) 0) ExifTool ref, 1) tag table ref, 2) data ref
sub ParseSeqParamSet($$$)
{
    my ($exifTool, $tagTablePtr, $dataPt) = @_;
    # initialize our bitstream object
    my $bstr = NewBitStream($dataPt) or return;
    my ($t, $i, $j, $n);
    # the messy nature of H.264 encoding makes it difficult to use
    # data-driven structure parsing, so I code it explicitely (yuck!)
    $t = GetIntN($bstr, 8);         # profile_idc
    GetIntN($bstr, 16);             # constraints and level_idc
    GetGolomb($bstr);               # seq_parameter_set_id
    if ($t >= 100) { # (ref b)
        $t = GetGolomb($bstr);      # chroma_format_idc
        if ($t == 3) {
            GetIntN($bstr, 1);      # separate_colour_plane_flag
            $n = 12;
        } else {
            $n = 8;
        }
        GetGolomb($bstr);           # bit_depth_luma_minus8
        GetGolomb($bstr);           # bit_depth_chroma_minus8
        GetIntN($bstr, 1);          # qpprime_y_zero_transform_bypass_flag
        DecodeScalingMatrices($bstr);
    }
    GetGolomb($bstr);               # log2_max_frame_num_minus4
    $t = GetGolomb($bstr);          # pic_order_cnt_type
    if ($t == 0) {
        GetGolomb($bstr);           # log2_max_pic_order_cnt_lsb_minus4
    } elsif ($t == 1) {
        GetIntN($bstr, 1);          # delta_pic_order_always_zero_flag
        GetGolomb($bstr);           # offset_for_non_ref_pic
        GetGolomb($bstr);           # offset_for_top_to_bottom_field
        $n = GetGolomb($bstr);      # num_ref_frames_in_pic_order_cnt_cycle
        for ($i=0; $i<$n; ++$i) {
            GetGolomb($bstr);       # offset_for_ref_frame[i]
        }
    }
    GetGolomb($bstr);               # num_ref_frames
    GetIntN($bstr, 1);              # gaps_in_frame_num_value_allowed_flag
    my $w = GetGolomb($bstr);       # pic_width_in_mbs_minus1
    my $h = GetGolomb($bstr);       # pic_height_in_map_units_minus1
    my $f = GetIntN($bstr, 1);      # frame_mbs_only_flag
    $f or GetIntN($bstr, 1);        # mb_adaptive_frame_field_flag
    GetIntN($bstr, 1);              # direct_8x8_inference_flag
    # convert image size to pixels
    $w = ($w + 1) * 16;
    $h = (2 - $f) * ($h + 1) * 16;
    # account for cropping (if any)
    $t = GetIntN($bstr, 1);         # frame_cropping_flag
    if ($t) {
        my $m = 4 - $f * 2;
        $w -=  4 * GetGolomb($bstr);# frame_crop_left_offset
        $w -=  4 * GetGolomb($bstr);# frame_crop_right_offset
        $h -= $m * GetGolomb($bstr);# frame_crop_top_offset
        $h -= $m * GetGolomb($bstr);# frame_crop_bottom_offset
    }
    # quick validity checks (just in case)
    return unless $$bstr{Mask};
    if ($w>=160 and $w<=4096 and $h>=120 and $h<=3072) {
        $exifTool->HandleTag($tagTablePtr, ImageWidth => $w);
        $exifTool->HandleTag($tagTablePtr, ImageHeight => $h);
        # (whew! -- so much work just to get ImageSize!!)
    }
    # return now unless interested in picture timing information
    return unless $parsePictureTiming;

    # parse vui parameters if they exist
    GetIntN($bstr, 1) or return;    # vui_parameters_present_flag
    $t = GetIntN($bstr, 1);         # aspect_ratio_info_present_flag
    if ($t) {
        $t = GetIntN($bstr, 8);     # aspect_ratio_idc
        if ($t == 255) {            # Extended_SAR ?
            GetIntN($bstr, 32);     # sar_width/sar_height
        }
    }
    $t = GetIntN($bstr, 1);         # overscan_info_present_flag
    GetIntN($bstr, 1) if $t;        # overscan_appropriate_flag
    $t = GetIntN($bstr, 1);         # video_signal_type_present_flag
    if ($t) {
        GetIntN($bstr, 4);          # video_format/video_full_range_flag
        $t = GetIntN($bstr, 1);     # colour_description_present_flag
        GetIntN($bstr, 24) if $t;   # colour_primaries/transfer_characteristics/matrix_coefficients
    }
    $t = GetIntN($bstr, 1);         # chroma_loc_info_present_flag
    if ($t) {
        GetGolomb($bstr);           # chroma_sample_loc_type_top_field
        GetGolomb($bstr);           # chroma_sample_loc_type_bottom_field
    }
    $t = GetIntN($bstr, 1);         # timing_info_present_flag
    if ($t) {
        return if BitsLeft($bstr) < 65;
        $$exifTool{VUI_units} = GetIntN($bstr, 32); # num_units_in_tick
        $$exifTool{VUI_scale} = GetIntN($bstr, 32); # time_scale
        GetIntN($bstr, 1);          # fixed_frame_rate_flag
    }
    my $hard;
    for ($j=0; $j<2; ++$j) {
        $t = GetIntN($bstr, 1);     # nal_/vcl_hrd_parameters_present_flag
        if ($t) {
            $$exifTool{VUI_hard} = 1;
            $hard = 1;
            $n = GetGolomb($bstr);  # cpb_cnt_minus1
            GetIntN($bstr, 8);      # bit_rate_scale/cpb_size_scale
            for ($i=0; $i<=$n; ++$i) {
                GetGolomb($bstr);   # bit_rate_value_minus1[SchedSelIdx]
                GetGolomb($bstr);   # cpb_size_value_minus1[SchedSelIdx]
                GetIntN($bstr, 1);  # cbr_flag[SchedSelIdx]
            }
            GetIntN($bstr, 5);      # initial_cpb_removal_delay_length_minus1
            $$exifTool{VUI_clen} = GetIntN($bstr, 5); # cpb_removal_delay_length_minus1
            $$exifTool{VUI_dlen} = GetIntN($bstr, 5); # dpb_output_delay_length_minus1
            $$exifTool{VUI_toff} = GetIntN($bstr, 5); # time_offset_length
        }
    }
    GetIntN($bstr, 1) if $hard;     # low_delay_hrd_flag
    $$exifTool{VUI_pic} = GetIntN($bstr, 1);    # pic_struct_present_flag
    # (don't yet decode the rest of the vui data)
}

#------------------------------------------------------------------------------
# Parse H.264 picture timing SEI message (payload type 1) (ref 1)
# Inputs) 0) ExifTool ref, 1) data ref
sub ParsePictureTiming($$)
{
    my ($exifTool, $dataPt) = @_;
    my $bstr = NewBitStream($dataPt) or return;
    my ($i, $t, $n);
    # the specification is very odd on this point: the following delays
    # exist if the VUI hardware parameters are present, or if
    # "determined by the application, by some means not specified" -- WTF??
    if ($$exifTool{VUI_hard}) {
        GetIntN($bstr, $$exifTool{VUI_clen} + 1);   # cpb_removal_delay
        GetIntN($bstr, $$exifTool{VUI_dlen} + 1);   # dpb_output_delay
    }
    if ($$exifTool{VUI_pic}) {
        $t = GetIntN($bstr, 4);     # pic_struct
        # determine NumClockTS ($n)
        $n = { 0=>1, 1=>1, 2=>1, 3=>2, 4=>2, 5=>3, 6=>3, 7=>2, 8=>3 }->{$t};
        $n or return;
        for ($i=0; $i<$n; ++$i) {
            $t = GetIntN($bstr, 1); # clock_timestamp_flag[i]
            next unless $t;
            my ($nu, $s, $m, $h, $o);
            GetIntN($bstr, 2);      # ct_type
            $nu = GetIntN($bstr, 1);# nuit_field_based_flag
            GetIntN($bstr, 5);      # counting_type
            $t = GetIntN($bstr, 1); # full_timestamp_flag
            GetIntN($bstr, 1);      # discontinuity_flag
            GetIntN($bstr, 1);      # cnt_dropped_flag
            GetIntN($bstr, 8);      # n_frames
            if ($t) {
                $s = GetIntN($bstr, 6); # seconds_value
                $m = GetIntN($bstr, 6); # minutes_value
                $h = GetIntN($bstr, 5); # hours_value
            } else {
                $t = GetIntN($bstr, 1); # seconds_flag
                if ($t) {
                    $s = GetIntN($bstr, 6); # seconds_value
                    $t = GetIntN($bstr, 1); # minutes_flag
                    if ($t) {
                        $m = GetIntN($bstr, 6); # minutes_value
                        $t = GetIntN($bstr, 1); # hours_flag
                        $h = GetIntN($bstr, 5) if $t;   # hours_value
                    }
                }
            }
            if ($$exifTool{VUI_toff}) {
                $o = GetIntN($bstr, $$exifTool{VUI_toff});  # time_offset
            }
            last;   # only parse the first clock timestamp found
        }
    }
}

#------------------------------------------------------------------------------
# Process H.264 Supplementary Enhancement Information (ref 1/PH)
# Inputs: 0) Exiftool ref, 1) dirInfo ref, 2) tag table ref
# Returns: 1 if we processed payload type 5
sub ProcessSEI($$)
{
    my ($exifTool, $dirInfo) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my $end = length($$dataPt);
    my $pos = 0;
    my ($type, $size, $index, $t);

    # scan through SEI payload for type 5 (the unregistered user data)
    for (;;) {
        $type = 0;
        for (;;) {
            return 0 if $pos >= $end;
            $t = Get8u($dataPt, $pos++);    # payload type
            $type += $t;
            last unless $t == 255;
        }
        return 0 if $type == 0x80;  # terminator (ref PH - maybe byte alignment bits?)
        $size = 0;
        for (;;) {
            return 0 if $pos >= $end;
            $t = Get8u($dataPt, $pos++);    # payload data length
            $size += $t;
            last unless $t == 255;
        }
        return 0 if $pos + $size > $end;
        if ($type == 1) {                   # picture timing information
            if ($parsePictureTiming) {
                my $buff = substr($$dataPt, $pos, $size);
                ParsePictureTiming($exifTool, $dataPt);
            }
        } elsif ($type == 5) {              # unregistered user data
            last; # exit loop to process user data now
        }
        $pos += $size;
    }

    # look for our 16-byte UUID
    # - plus "MDPM" for "ModifiedDVPackMeta"
    # - plus "GA94" for closed-caption data (not currently decoded)
    return 0 unless $size > 20 and substr($$dataPt, $pos, 20) eq
        "\x17\xee\x8c\x60\xf8\x4d\x11\xd9\x8c\xd6\x08\0\x20\x0c\x9a\x66MDPM";

    # load the GPS module because it contains conversion routines and
    # Composite tags needed for a number of tags we may be extracting
    require Image::ExifTool::GPS;
#
# parse the MDPM records in the UUID 17ee8c60f84d11d98cd60800200c9a66
# unregistered user data payload (ref PH)
#
    my $tagTablePtr = GetTagTable('Image::ExifTool::H264::MDPM');
    my $oldIndent = $$exifTool{INDENT};
    $$exifTool{INDENT} .= '| ';
    $end = $pos + $size;    # end of payload
    $pos += 20;             # skip UUID + "MDPM"
    my $num = Get8u($dataPt, $pos++);   # get entry count
    my $lastTag = 0;
    $exifTool->VerboseDir('MDPM', $num) if $exifTool->Options('Verbose');
    # walk through entries in the MDPM payload
    for ($index=0; $index<$num and $pos<$end; ++$index) {
        my $tag = Get8u($dataPt, $pos);
        if ($tag <= $lastTag) { # should be in numerical order (PH)
            $exifTool->Warn('Entries in MDPM directory are out of sequence');
            last;
        }
        $lastTag = $tag;
        my $buff = substr($$dataPt, $pos + 1, 4);
        my $from;
        if ($$tagTablePtr{$tag}) {
            # combine with next value(s) if necessary
            my $combine = $$tagTablePtr{$tag}{Combine};
            while ($combine) {
                last if $pos + 5 >= $end;
                my $t =  Get8u($dataPt, $pos + 5);
                last if $t != $lastTag + 1; # must be consecutive tag ID's
                $pos += 5;
                $buff .= substr($$dataPt, $pos + 1, 4);
                $from = $index unless defined $from;
                ++$index;
                ++$lastTag;
                --$combine;
            }
        } else {
            my %tagInfo = (
                Name        => sprintf('MDPM_0x%.2x', $tag),
                Description => sprintf('MDPM 0x%.2x', $tag),
                Unknown     => 1,
                PrintConv   => 'sprintf("0x%.8x", unpack("N", $val))',
            );
            Image::ExifTool::AddTagToTable($tagTablePtr, $tag, \%tagInfo);
        }
        $exifTool->HandleTag($tagTablePtr, $tag, undef,
            DataPt => \$buff,
            Size   => length($buff),
            Index  => defined $from ? "$from-$index" : $index,
        );
        $pos += 5;
    }
    $$exifTool{INDENT} = $oldIndent;
    return 1;
}

#------------------------------------------------------------------------------
# Extract information from H.264 video stream
# Inputs: 0) ExifTool ref, 1) data ref
sub ParseH264Video($$)
{
    my ($exifTool, $dataPt) = @_;
    my $verbose = $exifTool->Options('Verbose');
    my $out = $exifTool->Options('TextOut');
    my $tagTablePtr = GetTagTable('Image::ExifTool::H264::Main');
    my %parseNalUnit = ( 0x06 => 1, 0x07 => 1 );    # NAL unit types to parse
    my $len = length $$dataPt;
    my $pos = 0;
    while ($pos < $len) {
        my ($nextPos, $end);
        # find start of next NAL unit
        if ($$dataPt =~ /(\0{2,3}\x01)/g) {
            $nextPos = pos $$dataPt;
            $end = $nextPos - length $1;
            $pos or $pos = $nextPos, next;
        } else {
            last unless $pos;
            $nextPos = $end = $len;
        }
        last if $pos >= $len;
        # parse NAL unit from $pos to $end
        my $nal_unit_type = Get8u($dataPt, $pos);
        ++$pos;
        # check forbidden_zero_bit
        $nal_unit_type & 0x80 and $exifTool->Warn('H264 forbidden bit error'), last;
        $nal_unit_type &= 0x1f;
        # ignore this NAL unit unless we will parse it
        $parseNalUnit{$nal_unit_type} or $verbose or $pos = $nextPos, next;
        # read NAL unit (and convert all 0x000003's to 0x0000 as per spec.)
        my $buff = '';
        pos($$dataPt) = $pos + 1;
        while ($$dataPt =~ /\0\0\x03/g) {
            last if pos $$dataPt > $end;
            $buff .= substr($$dataPt, $pos, pos($$dataPt)-1-$pos);
            $pos = pos $$dataPt;
        }
        $buff .= substr($$dataPt, $pos, $end - $pos);
        if ($verbose > 1) {
            printf $out "  NAL Unit Type: 0x%x (%d bytes)\n",$nal_unit_type, length $buff;
            my %parms = ( Out => $out );
            $parms{MaxLen} = 96 if $verbose < 4;
            Image::ExifTool::HexDump(\$buff, undef, %parms) if $verbose > 2;
        }
        pos($$dataPt) = $pos = $nextPos;

        if ($nal_unit_type == 0x06) {       # sei_rbsp (supplemental enhancement info)

            if ($$exifTool{GotNAL06}) {
                # process only the first SEI unless ExtractEmbedded is set
                next unless $exifTool->Options('ExtractEmbedded');
                $$exifTool{DOC_NUM} = $$exifTool{GotNAL06};
            }
            my $result = ProcessSEI($exifTool, { DataPt => \$buff } );
            delete $$exifTool{DOC_NUM};
            next unless $result;
            $$exifTool{GotNAL06} = ($$exifTool{GotNAL06} || 0) + 1;

        } elsif ($nal_unit_type == 0x07) {  # sequence_parameter_set_rbsp

            # process this NAL unit type only once
            next if $$exifTool{GotNAL07};
            $$exifTool{GotNAL07} = 1;
            ParseSeqParamSet($exifTool, $tagTablePtr, \$buff);
        }
        # we were successful, so don't parse this NAL unit type again
        delete $parseNalUnit{$nal_unit_type};
    }
}

1;  # end

__END__

=head1 NAME

Image::ExifTool::H264 - Read meta information from H.264 video

=head1 SYNOPSIS

This module is used by Image::ExifTool

=head1 DESCRIPTION

This module contains routines required by Image::ExifTool to extract
information from H.264 video streams.

=head1 AUTHOR

Copyright 2003-2010, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://www.itu.int/rec/T-REC-H.264/e>

=item L<http://miffteevee.co.uk/documentation/development/H264Parser_8cpp-source.html>

=item L<http://ffmpeg.org/>

=back

=head1 SEE ALSO

L<Image::ExifTool::TagNames/H264 Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
