/**
Pixman static bindings.

Pixman is a library that provides low-level pixel manipulation
features such as image compositing and trapezoid rasterization.

More info: http://pixman.org/

Copyright: dayllenger 2019
License:   Boost License 1.0
*/
module pixman;

extern (C) nothrow @nogc:

enum PIXMAN_VERSION_MAJOR = 0;
enum PIXMAN_VERSION_MINOR = 34;
enum PIXMAN_VERSION_MICRO = 0;

/*
 * Boolean
 */
alias pixman_bool_t = int;

/*
 * Fixpoint numbers
 */
alias pixman_fixed_16_16_t = int;
alias pixman_fixed_t = pixman_fixed_16_16_t;

enum pixman_fixed_e = cast(pixman_fixed_t)1;
enum pixman_fixed_1 = pixman_int_to_fixed(1);
enum pixman_fixed_1_minus_e = pixman_fixed_1 - pixman_fixed_e;
enum pixman_fixed_minus_1 = pixman_int_to_fixed(-1);

int            pixman_fixed_to_int    (pixman_fixed_t f) { return cast(int)(f >> 16); }
pixman_fixed_t pixman_int_to_fixed    (int i)            { return cast(pixman_fixed_t)(i << 16); }
double         pixman_fixed_to_double (pixman_fixed_t f) { return cast(double)(f / cast(double)pixman_fixed_1); }
pixman_fixed_t pixman_double_to_fixed (double d)         { return cast(pixman_fixed_t)(d * 65_536.0); }
pixman_fixed_t pixman_fixed_frac      (pixman_fixed_t f) { return f & pixman_fixed_1_minus_e; }
pixman_fixed_t pixman_fixed_floor     (pixman_fixed_t f) { return f & ~pixman_fixed_1_minus_e; }
pixman_fixed_t pixman_fixed_ceil      (pixman_fixed_t f) { return pixman_fixed_floor(f + pixman_fixed_1_minus_e); }
pixman_fixed_t pixman_fixed_fraction  (pixman_fixed_t f) { return f & pixman_fixed_1_minus_e; }
pixman_fixed_t pixman_fixed_mod_2     (pixman_fixed_t f) { return f & (pixman_fixed_1 | pixman_fixed_1_minus_e); }

/*
 * Misc structs
 */

struct pixman_color_t
{
    ushort red;
    ushort green;
    ushort blue;
    ushort alpha;
}

struct pixman_point_fixed_t
{
    pixman_fixed_t x;
    pixman_fixed_t y;
}

struct pixman_line_fixed_t
{
    pixman_point_fixed_t p1, p2;
}

/*
 * Fixed point matrices
 */

struct pixman_vector_t
{
    pixman_fixed_t[3] vector;
}

struct pixman_transform_t
{
    pixman_fixed_t[3][3] matrix;
}

void pixman_transform_init_identity(pixman_transform_t* matrix);
pixman_bool_t pixman_transform_point_3d(
    const pixman_transform_t* transform,
    pixman_vector_t* vector);
pixman_bool_t pixman_transform_point(
    const pixman_transform_t* transform,
    pixman_vector_t* vector);
pixman_bool_t pixman_transform_multiply(
    pixman_transform_t* dst,
    const pixman_transform_t* l,
    const pixman_transform_t* r);
void pixman_transform_init_scale(
    pixman_transform_t* t,
    pixman_fixed_t sx,
    pixman_fixed_t sy);
pixman_bool_t pixman_transform_scale(
    pixman_transform_t* forward,
    pixman_transform_t* reverse,
    pixman_fixed_t sx,
    pixman_fixed_t sy);
void pixman_transform_init_rotate(
    pixman_transform_t* t,
    pixman_fixed_t cos,
    pixman_fixed_t sin);
pixman_bool_t pixman_transform_rotate(
    pixman_transform_t* forward,
    pixman_transform_t* reverse,
    pixman_fixed_t cos,
    pixman_fixed_t sin);
void pixman_transform_init_translate(
    pixman_transform_t* t,
    pixman_fixed_t tx,
    pixman_fixed_t ty);
pixman_bool_t pixman_transform_translate(
    pixman_transform_t* forward,
    pixman_transform_t* reverse,
    pixman_fixed_t tx,
    pixman_fixed_t ty);
pixman_bool_t pixman_transform_bounds(
    const pixman_transform_t* matrix,
    pixman_box16_t* b);
pixman_bool_t pixman_transform_invert(
    pixman_transform_t* dst,
    const pixman_transform_t* src);
pixman_bool_t pixman_transform_is_identity(const pixman_transform_t* t);
pixman_bool_t pixman_transform_is_scale(const pixman_transform_t* t);
pixman_bool_t pixman_transform_is_int_translate(const pixman_transform_t* t);
pixman_bool_t pixman_transform_is_inverse(
    const pixman_transform_t* a,
    const pixman_transform_t* b);

enum pixman_repeat_t
{
    none,
    normal,
    pad,
    reflect
}

enum pixman_filter_t
{
    fast,
    good,
    best,
    nearest,
    bilinear,
    convolution,

    /* The separable_convolution filter takes the following parameters:
     *
     *         width:           integer given as 16.16 fixpoint number
     *         height:          integer given as 16.16 fixpoint number
     *         x_phase_bits:    integer given as 16.16 fixpoint
     *         y_phase_bits:    integer given as 16.16 fixpoint
     *         xtables:         (1 << x_phase_bits) tables of size width
     *         ytables:         (1 << y_phase_bits) tables of size height
     *
     * When sampling at (x, y), the location is first rounded to one of
     * n_x_phases * n_y_phases subpixel positions. These subpixel positions
     * determine an xtable and a ytable to use.
     *
     * Conceptually a width x height matrix is then formed in which each entry
     * is the product of the corresponding entries in the x and y tables.
     * This matrix is then aligned with the image pixels such that its center
     * is as close as possible to the subpixel location chosen earlier. Then
     * the image is convolved with the matrix and the resulting pixel returned.
     */
    separable_convolution
}

enum pixman_op_t
{
    clear = 0x00,
    src = 0x01,
    dst = 0x02,
    over = 0x03,
    over_reverse = 0x04,
    in_ = 0x05,
    in_reverse = 0x06,
    out_ = 0x07,
    out_reverse = 0x08,
    atop = 0x09,
    atop_reverse = 0x0a,
    xor = 0x0b,
    add = 0x0c,
    saturate = 0x0d,

    disjoint_clear = 0x10,
    disjoint_src = 0x11,
    disjoint_dst = 0x12,
    disjoint_over = 0x13,
    disjoint_over_reverse = 0x14,
    disjoint_in = 0x15,
    disjoint_in_reverse = 0x16,
    disjoint_out = 0x17,
    disjoint_out_reverse = 0x18,
    disjoint_atop = 0x19,
    disjoint_atop_reverse = 0x1a,
    disjoint_xor = 0x1b,

    conjoint_clear = 0x20,
    conjoint_src = 0x21,
    conjoint_dst = 0x22,
    conjoint_over = 0x23,
    conjoint_over_reverse = 0x24,
    conjoint_in = 0x25,
    conjoint_in_reverse = 0x26,
    conjoint_out = 0x27,
    conjoint_out_reverse = 0x28,
    conjoint_atop = 0x29,
    conjoint_atop_reverse = 0x2a,
    conjoint_xor = 0x2b,

    multiply = 0x30,
    screen = 0x31,
    overlay = 0x32,
    darken = 0x33,
    lighten = 0x34,
    color_dodge = 0x35,
    color_burn = 0x36,
    hard_light = 0x37,
    soft_light = 0x38,
    difference = 0x39,
    exclusion = 0x3a,
    hsl_hue = 0x3b,
    hsl_saturation = 0x3c,
    hsl_color = 0x3d,
    hsl_luminosity = 0x3e
}

/*
 * Regions
 */

struct pixman_region16_data_t
{
    long size;
    long numRects;
    /* pixman_box16_t[size] rects;   in memory but not explicitly declared */
}

struct pixman_box16_t
{
    short x1, y1, x2, y2;
}

struct pixman_region16_t
{
    pixman_box16_t extents;
    pixman_region16_data_t* data;
}

enum pixman_region_overlap_t
{
    OUT,
    IN,
    PART
}

/* creation/destruction */
void pixman_region_init(pixman_region16_t* region);
void pixman_region_init_rect(
    pixman_region16_t* region,
    int x, int y, uint width, uint height);
pixman_bool_t pixman_region_init_rects(
    pixman_region16_t* region,
    const pixman_box16_t* boxes, int count);
void pixman_region_init_with_extents(
    pixman_region16_t* region,
    pixman_box16_t* extents);
void pixman_region_init_from_image(
    pixman_region16_t* region,
    pixman_image_t* image);
void pixman_region_fini(pixman_region16_t* region);

/* manipulation */
void pixman_region_translate(pixman_region16_t* region, int x, int y);
pixman_bool_t pixman_region_copy(
    pixman_region16_t* dest,
    pixman_region16_t* source);
pixman_bool_t pixman_region_intersect(
    pixman_region16_t* new_reg,
    pixman_region16_t* reg1,
    pixman_region16_t* reg2);
pixman_bool_t pixman_region_union(
    pixman_region16_t* new_reg,
    pixman_region16_t* reg1,
    pixman_region16_t* reg2);
pixman_bool_t pixman_region_union_rect(
    pixman_region16_t* dest,
    pixman_region16_t* source,
    int x, int y, uint width, uint height);
pixman_bool_t pixman_region_intersect_rect(
    pixman_region16_t* dest,
    pixman_region16_t* source,
    int x, int y, uint width, uint height);
pixman_bool_t pixman_region_subtract(
    pixman_region16_t* reg_d,
    pixman_region16_t* reg_m,
    pixman_region16_t* reg_s);
pixman_bool_t pixman_region_inverse(
    pixman_region16_t* new_reg,
    pixman_region16_t* reg1,
    pixman_box16_t* inv_rect);
pixman_bool_t pixman_region_contains_point(
    pixman_region16_t* region,
    int x, int y,
    pixman_box16_t* box);
pixman_region_overlap_t pixman_region_contains_rectangle(pixman_region16_t* region,
    pixman_box16_t* prect);
pixman_bool_t pixman_region_not_empty(pixman_region16_t* region);
pixman_box16_t* pixman_region_extents(pixman_region16_t* region);
int pixman_region_n_rects(pixman_region16_t* region);
pixman_box16_t* pixman_region_rectangles(pixman_region16_t* region, int* n_rects);
pixman_bool_t pixman_region_equal(pixman_region16_t* region1, pixman_region16_t* region2);
pixman_bool_t pixman_region_selfcheck(pixman_region16_t* region);
void pixman_region_reset(pixman_region16_t* region, pixman_box16_t* box);
void pixman_region_clear(pixman_region16_t* region);

/*
 * 32 bit regions
 */

struct pixman_region32_data_t
{
    long size;
    long numRects;
    /* pixman_box32_t[size] rects;   in memory but not explicitly declared */
}

struct pixman_box32_t
{
    int x1, y1, x2, y2;
}

struct pixman_region32_t
{
    pixman_box32_t extents;
    pixman_region32_data_t* data;
}

/* creation/destruction */
void pixman_region32_init(pixman_region32_t* region);
void pixman_region32_init_rect(
    pixman_region32_t* region,
    int x, int y, uint width, uint height);
pixman_bool_t pixman_region32_init_rects(
    pixman_region32_t* region,
    const pixman_box32_t* boxes,
    int count);
void pixman_region32_init_with_extents(
    pixman_region32_t* region,
    pixman_box32_t* extents);
void pixman_region32_init_from_image(
    pixman_region32_t* region,
    pixman_image_t* image);
void pixman_region32_fini(pixman_region32_t* region);

/* manipulation */
void pixman_region32_translate(
    pixman_region32_t* region,
    int x, int y);
pixman_bool_t pixman_region32_copy(
    pixman_region32_t* dest,
    pixman_region32_t* source);
pixman_bool_t pixman_region32_intersect(
    pixman_region32_t* new_reg,
    pixman_region32_t* reg1,
    pixman_region32_t* reg2);
pixman_bool_t pixman_region32_union(
    pixman_region32_t* new_reg,
    pixman_region32_t* reg1,
    pixman_region32_t* reg2);
pixman_bool_t pixman_region32_intersect_rect(
    pixman_region32_t* dest,
    pixman_region32_t* source,
    int x, int y, uint width, uint height);
pixman_bool_t pixman_region32_union_rect(
    pixman_region32_t* dest,
    pixman_region32_t* source,
    int x, int y, uint width, uint height);
pixman_bool_t pixman_region32_subtract(
    pixman_region32_t* reg_d,
    pixman_region32_t* reg_m,
    pixman_region32_t* reg_s);
pixman_bool_t pixman_region32_inverse(
    pixman_region32_t* new_reg,
    pixman_region32_t* reg1,
    pixman_box32_t* inv_rect);
pixman_bool_t pixman_region32_contains_point(
    pixman_region32_t* region,
    int x, int y,
    pixman_box32_t* box);
pixman_region_overlap_t pixman_region32_contains_rectangle(
    pixman_region32_t* region,
    pixman_box32_t* prect);
pixman_bool_t pixman_region32_not_empty(const pixman_region32_t* region);
pixman_box32_t* pixman_region32_extents(pixman_region32_t* region);
int pixman_region32_n_rects(pixman_region32_t* region);
pixman_box32_t* pixman_region32_rectangles(pixman_region32_t* region, int* n_rects);
pixman_bool_t pixman_region32_equal(pixman_region32_t* region1, pixman_region32_t* region2);
pixman_bool_t pixman_region32_selfcheck(pixman_region32_t* region);
void pixman_region32_reset(pixman_region32_t* region, pixman_box32_t* box);
void pixman_region32_clear(pixman_region32_t* region);

/* Copy / Fill / Misc */
pixman_bool_t pixman_blt(
    uint* src_bits,
    uint* dst_bits,
    int src_stride,
    int dst_stride,
    int src_bpp,
    int dst_bpp,
    int src_x,
    int src_y,
    int dest_x,
    int dest_y,
    int width,
    int height);
pixman_bool_t pixman_fill(
    uint* bits,
    int stride,
    int bpp,
    int x,
    int y,
    int width,
    int height,
    uint _xor);

int pixman_version();
const(char)* pixman_version_string();

/*
 * Images
 */

union pixman_image_t;

alias pixman_read_memory_func_t = uint function(const void* src, int size);
alias pixman_write_memory_func_t = void function(void* dst, uint value, int size);
alias pixman_image_destroy_func_t = void function(pixman_image_t* image, void* data);

struct pixman_gradient_stop_t
{
    pixman_fixed_t x;
    pixman_color_t color;
}

enum PIXMAN_MAX_INDEXED = 256;
alias pixman_index_type = ubyte;

struct pixman_indexed_t
{
    pixman_bool_t color;
    uint[PIXMAN_MAX_INDEXED] rgba;
    pixman_index_type[32_768] ent;
}

/*
 * While the protocol is generous in format support, the
 * sample implementation allows only packed RGB and GBR
 * representations for data to simplify software rendering
 */
int pixman_format(int bpp, int type, int a, int r, int g, int b)
{
    return (bpp << 24) | (type << 16) | (a << 12) | (r << 8) | (g << 4) | b;
}

int pixman_format_bpp  (int f) { return (f >> 24); }
int pixman_format_type (int f) { return (f >> 16) & 0xff; }
int pixman_format_a    (int f) { return (f >> 12) & 0x0f; }
int pixman_format_r    (int f) { return (f >> 8) & 0x0f; }
int pixman_format_g    (int f) { return (f >> 4) & 0x0f; }
int pixman_format_b    (int f) { return f & 0x0f; }
int pixman_format_rgb  (int f) { return f & 0xfff; }
int pixman_format_vis  (int f) { return f & 0xffff; }

int pixman_format_depth(int f)
{
    return pixman_format_a(f) + pixman_format_r(f) + pixman_format_g(f) + pixman_format_b(f);
}

enum
{
    PIXMAN_TYPE_OTHER = 0,
    PIXMAN_TYPE_A,
    PIXMAN_TYPE_ARGB,
    PIXMAN_TYPE_ABGR,
    PIXMAN_TYPE_COLOR,
    PIXMAN_TYPE_GRAY,
    PIXMAN_TYPE_YUY2,
    PIXMAN_TYPE_YV12,
    PIXMAN_TYPE_BGRA,
    PIXMAN_TYPE_RGBA,
    PIXMAN_TYPE_ARGB_SRGB,
}

bool pixman_format_color(int f)
{
    return pixman_format_type(f) == PIXMAN_TYPE_ARGB || pixman_format_type(f) == PIXMAN_TYPE_ABGR ||
           pixman_format_type(f) == PIXMAN_TYPE_BGRA || pixman_format_type(f) == PIXMAN_TYPE_RGBA;
}

/* 32bpp formats */
enum pixman_format_code_t
{
    a8r8g8b8 = pixman_format(32, PIXMAN_TYPE_ARGB, 8, 8, 8, 8),
    x8r8g8b8 = pixman_format(32, PIXMAN_TYPE_ARGB, 0, 8, 8, 8),
    a8b8g8r8 = pixman_format(32, PIXMAN_TYPE_ABGR, 8, 8, 8, 8),
    x8b8g8r8 = pixman_format(32, PIXMAN_TYPE_ABGR, 0, 8, 8, 8),
    b8g8r8a8 = pixman_format(32, PIXMAN_TYPE_BGRA, 8, 8, 8, 8),
    b8g8r8x8 = pixman_format(32, PIXMAN_TYPE_BGRA, 0, 8, 8, 8),
    r8g8b8a8 = pixman_format(32, PIXMAN_TYPE_RGBA, 8, 8, 8, 8),
    r8g8b8x8 = pixman_format(32, PIXMAN_TYPE_RGBA, 0, 8, 8, 8),
    x14r6g6b6 = pixman_format(32, PIXMAN_TYPE_ARGB, 0, 6, 6, 6),
    x2r10g10b10 = pixman_format(32, PIXMAN_TYPE_ARGB, 0, 10, 10, 10),
    a2r10g10b10 = pixman_format(32, PIXMAN_TYPE_ARGB, 2, 10, 10, 10),
    x2b10g10r10 = pixman_format(32, PIXMAN_TYPE_ABGR, 0, 10, 10, 10),
    a2b10g10r10 = pixman_format(32, PIXMAN_TYPE_ABGR, 2, 10, 10, 10),

    /* sRGB formats */
    a8r8g8b8_sRGB = pixman_format(32, PIXMAN_TYPE_ARGB_SRGB, 8, 8, 8, 8),

    /* 24bpp formats */
    r8g8b8 = pixman_format(24, PIXMAN_TYPE_ARGB, 0, 8, 8, 8),
    b8g8r8 = pixman_format(24, PIXMAN_TYPE_ABGR, 0, 8, 8, 8),

    /* 16bpp formats */
    r5g6b5 = pixman_format(16, PIXMAN_TYPE_ARGB, 0, 5, 6, 5),
    b5g6r5 = pixman_format(16, PIXMAN_TYPE_ABGR, 0, 5, 6, 5),

    a1r5g5b5 = pixman_format(16, PIXMAN_TYPE_ARGB, 1, 5, 5, 5),
    x1r5g5b5 = pixman_format(16, PIXMAN_TYPE_ARGB, 0, 5, 5, 5),
    a1b5g5r5 = pixman_format(16, PIXMAN_TYPE_ABGR, 1, 5, 5, 5),
    x1b5g5r5 = pixman_format(16, PIXMAN_TYPE_ABGR, 0, 5, 5, 5),
    a4r4g4b4 = pixman_format(16, PIXMAN_TYPE_ARGB, 4, 4, 4, 4),
    x4r4g4b4 = pixman_format(16, PIXMAN_TYPE_ARGB, 0, 4, 4, 4),
    a4b4g4r4 = pixman_format(16, PIXMAN_TYPE_ABGR, 4, 4, 4, 4),
    x4b4g4r4 = pixman_format(16, PIXMAN_TYPE_ABGR, 0, 4, 4, 4),

    /* 8bpp formats */
    a8 = pixman_format(8, PIXMAN_TYPE_A, 8, 0, 0, 0),
    r3g3b2 = pixman_format(8, PIXMAN_TYPE_ARGB, 0, 3, 3, 2),
    b2g3r3 = pixman_format(8, PIXMAN_TYPE_ABGR, 0, 3, 3, 2),
    a2r2g2b2 = pixman_format(8, PIXMAN_TYPE_ARGB, 2, 2, 2, 2),
    a2b2g2r2 = pixman_format(8, PIXMAN_TYPE_ABGR, 2, 2, 2, 2),

    c8 = pixman_format(8, PIXMAN_TYPE_COLOR, 0, 0, 0, 0),
    g8 = pixman_format(8, PIXMAN_TYPE_GRAY, 0, 0, 0, 0),

    x4a4 = pixman_format(8, PIXMAN_TYPE_A, 4, 0, 0, 0),

    x4c4 = pixman_format(8, PIXMAN_TYPE_COLOR, 0, 0, 0, 0),
    x4g4 = pixman_format(8, PIXMAN_TYPE_GRAY, 0, 0, 0, 0),

    /* 4bpp formats */
    a4 = pixman_format(4, PIXMAN_TYPE_A, 4, 0, 0, 0),
    r1g2b1 = pixman_format(4, PIXMAN_TYPE_ARGB, 0, 1, 2, 1),
    b1g2r1 = pixman_format(4, PIXMAN_TYPE_ABGR, 0, 1, 2, 1),
    a1r1g1b1 = pixman_format(4, PIXMAN_TYPE_ARGB, 1, 1, 1, 1),
    a1b1g1r1 = pixman_format(4, PIXMAN_TYPE_ABGR, 1, 1, 1, 1),

    c4 = pixman_format(4, PIXMAN_TYPE_COLOR, 0, 0, 0, 0),
    g4 = pixman_format(4, PIXMAN_TYPE_GRAY, 0, 0, 0, 0),

    /* 1bpp formats */
    a1 = pixman_format(1, PIXMAN_TYPE_A, 1, 0, 0, 0),
    g1 = pixman_format(1, PIXMAN_TYPE_GRAY, 0, 0, 0, 0),

    /* YUV formats */
    yuy2 = pixman_format(16, PIXMAN_TYPE_YUY2, 0, 0, 0, 0),
    yv12 = pixman_format(12, PIXMAN_TYPE_YV12, 0, 0, 0, 0)
}

/* Querying supported format values. */
pixman_bool_t pixman_format_supported_destination(pixman_format_code_t format);
pixman_bool_t pixman_format_supported_source(pixman_format_code_t format);

/* Constructors */
pixman_image_t* pixman_image_create_solid_fill(const pixman_color_t* color);
pixman_image_t* pixman_image_create_linear_gradient(
    const pixman_point_fixed_t* p1,
    const pixman_point_fixed_t* p2,
    const pixman_gradient_stop_t* stops,
    int n_stops);
pixman_image_t* pixman_image_create_radial_gradient(
    const pixman_point_fixed_t* inner,
    const pixman_point_fixed_t* outer,
    pixman_fixed_t inner_radius,
    pixman_fixed_t outer_radius,
    const pixman_gradient_stop_t* stops,
    int n_stops);
pixman_image_t* pixman_image_create_conical_gradient(
    const pixman_point_fixed_t* center,
    pixman_fixed_t angle,
    const pixman_gradient_stop_t* stops,
    int n_stops);
pixman_image_t* pixman_image_create_bits(
    pixman_format_code_t format,
    int width,
    int height,
    uint* bits,
    int rowstride_bytes);
pixman_image_t* pixman_image_create_bits_no_clear(
    pixman_format_code_t format,
    int width,
    int height,
    uint* bits,
    int rowstride_bytes);

/* Destructor */
pixman_image_t* pixman_image_ref(pixman_image_t* image);
pixman_bool_t pixman_image_unref(pixman_image_t* image);

void pixman_image_set_destroy_function(pixman_image_t* image,
    pixman_image_destroy_func_t func, void* data);
void* pixman_image_get_destroy_data(pixman_image_t* image);

/* Set properties */
pixman_bool_t pixman_image_set_clip_region(
    pixman_image_t* image,
    pixman_region16_t* region);
pixman_bool_t pixman_image_set_clip_region32(
    pixman_image_t* image,
    pixman_region32_t* region);
void pixman_image_set_has_client_clip(
    pixman_image_t* image,
    pixman_bool_t clien_clip);
pixman_bool_t pixman_image_set_transform(
    pixman_image_t* image,
    const pixman_transform_t* transform);
void pixman_image_set_repeat(
    pixman_image_t* image,
    pixman_repeat_t repeat);
pixman_bool_t pixman_image_set_filter(
    pixman_image_t* image,
    pixman_filter_t filter,
    const pixman_fixed_t* filter_params,
    int n_filter_params);
void pixman_image_set_source_clipping(
    pixman_image_t* image,
    pixman_bool_t source_clipping);
void pixman_image_set_alpha_map(
    pixman_image_t* image,
    pixman_image_t* alpha_map,
    short x, short y);
void pixman_image_set_component_alpha(
    pixman_image_t* image,
    pixman_bool_t component_alpha);
pixman_bool_t pixman_image_get_component_alpha(pixman_image_t* image);
void pixman_image_set_accessors(
    pixman_image_t* image,
    pixman_read_memory_func_t read_func,
    pixman_write_memory_func_t write_func);
void pixman_image_set_indexed(
    pixman_image_t* image,
    const pixman_indexed_t* indexed);
uint* pixman_image_get_data(pixman_image_t* image);
int pixman_image_get_width(pixman_image_t* image);
int pixman_image_get_height(pixman_image_t* image);
int pixman_image_get_stride(pixman_image_t* image); /* in bytes */
int pixman_image_get_depth(pixman_image_t* image);
pixman_format_code_t pixman_image_get_format(pixman_image_t* image);

enum pixman_kernel_t
{
    impulse,
    box,
    linear,
    cubic,
    gaussian,
    lanczos2,
    lanczos3,
    lanczos3_stretched /* Jim Blinn's 'nice' filter */
}

/* Create the parameter list for a SEPARABLE_CONVOLUTION filter
 * with the given kernels and scale parameters.
 */
pixman_fixed_t* pixman_filter_create_separable_convolution(
    int* n_values,
    pixman_fixed_t scale_x,
    pixman_fixed_t scale_y,
    pixman_kernel_t reconstruct_x,
    pixman_kernel_t reconstruct_y,
    pixman_kernel_t sample_x,
    pixman_kernel_t sample_y,
    int subsample_bits_x,
    int subsample_bits_y);

pixman_bool_t pixman_image_fill_boxes(
    pixman_op_t op,
    pixman_image_t* dest,
    const pixman_color_t* color,
    int n_boxes,
    const pixman_box32_t* boxes);

/* Composite */
pixman_bool_t pixman_compute_composite_region(
    pixman_region16_t* region,
    pixman_image_t* src_image,
    pixman_image_t* mask_image,
    pixman_image_t* dest_image,
    short src_x,
    short src_y,
    short mask_x,
    short mask_y,
    short dest_x,
    short dest_y,
    ushort width,
    ushort height);
void pixman_image_composite32(
    pixman_op_t op,
    pixman_image_t* src,
    pixman_image_t* mask,
    pixman_image_t* dest,
    int src_x,
    int src_y,
    int mask_x,
    int mask_y,
    int dest_x,
    int dest_y,
    int width,
    int height);

/*
 * Glyphs
 */
struct pixman_glyph_cache_t;
struct pixman_glyph_t
{
    int x, y;
    const void* glyph;
}

pixman_glyph_cache_t* pixman_glyph_cache_create();
void pixman_glyph_cache_destroy(pixman_glyph_cache_t* cache);
void pixman_glyph_cache_freeze(pixman_glyph_cache_t* cache);
void pixman_glyph_cache_thaw(pixman_glyph_cache_t* cache);
const(void)* pixman_glyph_cache_lookup(
    pixman_glyph_cache_t* cache,
    void* font_key,
    void* glyph_key);
const(void)* pixman_glyph_cache_insert(
    pixman_glyph_cache_t* cache,
    void* font_key,
    void* glyph_key,
    int origin_x,
    int origin_y,
    pixman_image_t* glyph_image);
void pixman_glyph_cache_remove(
    pixman_glyph_cache_t* cache,
    void* font_key,
    void* glyph_key);
void pixman_glyph_get_extents(
    pixman_glyph_cache_t* cache,
    int n_glyphs,
    pixman_glyph_t* glyphs,
    pixman_box32_t* extents);
pixman_format_code_t pixman_glyph_get_mask_format(
    pixman_glyph_cache_t* cache,
    int n_glyphs,
    const pixman_glyph_t* glyphs);

void pixman_composite_glyphs(
    pixman_op_t op,
    pixman_image_t* src,
    pixman_image_t* dest,
    pixman_format_code_t mask_format,
    int src_x,
    int src_y,
    int mask_x,
    int mask_y,
    int dest_x,
    int dest_y,
    int width,
    int height,
    pixman_glyph_cache_t* cache,
    int n_glyphs,
    const pixman_glyph_t* glyphs);
void pixman_composite_glyphs_no_mask(
    pixman_op_t op,
    pixman_image_t* src,
    pixman_image_t* dest,
    int src_x,
    int src_y,
    int dest_x,
    int dest_y,
    pixman_glyph_cache_t* cache,
    int n_glyphs,
    const pixman_glyph_t* glyphs);

/*
 * Trapezoids
 */

/*
 * An edge structure.  This represents a single polygon edge
 * and can be quickly stepped across small or large gaps in the
 * sample grid
 */
struct pixman_edge_t
{
    pixman_fixed_t x;
    pixman_fixed_t e;
    pixman_fixed_t stepx;
    pixman_fixed_t signdx;
    pixman_fixed_t dy;
    pixman_fixed_t dx;

    pixman_fixed_t stepx_small;
    pixman_fixed_t stepx_big;
    pixman_fixed_t dx_small;
    pixman_fixed_t dx_big;
}

struct pixman_trapezoid_t
{
    pixman_fixed_t top, bottom;
    pixman_line_fixed_t left, right;
}

struct pixman_triangle_t
{
    pixman_point_fixed_t p1, p2, p3;
}

/* whether 't' is a well defined not obviously empty trapezoid */
bool pixman_trapezoid_valid(ref const pixman_trapezoid_t t)
{
    return t.left.p1.y != t.left.p2.y && t.right.p1.y != t.right.p2.y && t.bottom > t.top;
}

struct pixman_span_fix_t
{
    pixman_fixed_t l, r, y;
}

struct pixman_trap_t
{
    pixman_span_fix_t top, bot;
}

pixman_fixed_t pixman_sample_ceil_y(pixman_fixed_t y, int bpp);
pixman_fixed_t pixman_sample_floor_y(pixman_fixed_t y, int bpp);
void pixman_edge_step(pixman_edge_t* e, int n);
void pixman_edge_init(
    pixman_edge_t* e,
    int bpp,
    pixman_fixed_t y_start,
    pixman_fixed_t x_top,
    pixman_fixed_t y_top,
    pixman_fixed_t x_bot,
    pixman_fixed_t y_bot);
void pixman_line_fixed_edge_init(
    pixman_edge_t* e,
    int bpp,
    pixman_fixed_t y,
    const pixman_line_fixed_t* line,
    int x_off,
    int y_off);
void pixman_rasterize_edges(
    pixman_image_t* image,
    pixman_edge_t* l,
    pixman_edge_t* r,
    pixman_fixed_t t,
    pixman_fixed_t b);
void pixman_add_traps(
    pixman_image_t* image,
    short x_off,
    short y_off,
    int ntrap,
    const pixman_trap_t* traps);
void pixman_add_trapezoids(
    pixman_image_t* image,
    short x_off,
    int y_off,
    int ntraps,
    const pixman_trapezoid_t* traps);
void pixman_rasterize_trapezoid(
    pixman_image_t* image,
    const pixman_trapezoid_t* trap,
    int x_off,
    int y_off);
void pixman_composite_trapezoids(
    pixman_op_t op,
    pixman_image_t* src,
    pixman_image_t* dst,
    pixman_format_code_t mask_format,
    int x_src,
    int y_src,
    int x_dst,
    int y_dst,
    int n_traps,
    const pixman_trapezoid_t* traps);
void pixman_composite_triangles(
    pixman_op_t op,
    pixman_image_t* src,
    pixman_image_t* dst,
    pixman_format_code_t mask_format,
    int x_src,
    int y_src,
    int x_dst,
    int y_dst,
    int n_tris,
    const pixman_triangle_t* tris);
void pixman_add_triangles(
    pixman_image_t* image,
    int x_off,
    int y_off,
    int n_tris,
    const pixman_triangle_t* tris);
