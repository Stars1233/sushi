//! Exact A5/A6 masked-coefficient hoist; original row arithmetic retained.
const std = @import("std");
const mlx = @import("mlx.zig");
const Arr = mlx.mlx_array;
const Ops = @import("glm5_model.zig").Ops;
const Linear = @import("glm5_model.zig").Linear;
// The per-row dot/update order is inherited from glm5_decode's MLX-derived qmv_fast.
// Each admitted width occupies one complete row tile, so its offset is constant.
const SOURCE =
    \\const int lane = int(thread_index_in_simdgroup);
    \\const int output0 = int(threadgroup_position_in_grid.x) * 8 + int(simdgroup_index_in_threadgroup) * 2;
    \\const int token0 = 0;
    \\const device uint8_t* codes = reinterpret_cast<const device uint8_t*>(w);
    \\constexpr int V = BITS == 5 ? 16 : 8;
    \\float result[R][2];
    \\for (int m = 0; m < R; ++m) for (int r = 0; r < 2; ++r) result[m][r] = 0.0f;
    \\for (int k = 0; k < K; k += 32 * V) {
    \\  float local[R][V];
    \\  float sum[R];
    \\  for (int m = 0; m < R; ++m) {
    \\    sum[m] = 0.0f;
    \\    if (BITS == 5) {
    \\      for (int i = 0; i < 16; i += 8) {
    \\        const int at = (token0+m)*K+k+lane*16+i;
    \\        if (token0+m < M) sum[m] += x[at]+x[at+1]+x[at+2]+x[at+3]+x[at+4]+x[at+5]+x[at+6]+x[at+7];
    \\        local[m][i] = token0+m < M ? float(x[at]) : 0.0f;
    \\        local[m][i+1] = token0+m < M ? float(x[at+1])/32.0f : 0.0f;
    \\        local[m][i+2] = token0+m < M ? float(x[at+2])/4.0f : 0.0f;
    \\        local[m][i+3] = token0+m < M ? float(x[at+3])/128.0f : 0.0f;
    \\        local[m][i+4] = token0+m < M ? float(x[at+4])/16.0f : 0.0f;
    \\        local[m][i+5] = token0+m < M ? float(x[at+5])/2.0f : 0.0f;
    \\        local[m][i+6] = token0+m < M ? float(x[at+6])/64.0f : 0.0f;
    \\        local[m][i+7] = token0+m < M ? float(x[at+7])/8.0f : 0.0f;
    \\      }
    \\    } else if (BITS == 6) {
    \\      for (int i = 0; i < 8; i += 4) {
    \\        const int at = (token0+m)*K+k+lane*8+i;
    \\        if (token0+m < M) sum[m] += x[at]+x[at+1]+x[at+2]+x[at+3];
    \\        local[m][i] = token0+m < M ? float(x[at]) : 0.0f;
    \\        local[m][i+1] = token0+m < M ? float(x[at+1])/64.0f : 0.0f;
    \\        local[m][i+2] = token0+m < M ? float(x[at+2])/16.0f : 0.0f;
    \\        local[m][i+3] = token0+m < M ? float(x[at+3])/4.0f : 0.0f;
    \\      }
    \\    } else {
    \\    for (int i = 0; i < 8; ++i) {
    \\      const float value = token0 + m < M ? float(x[(token0 + m) * K + k + lane * 8 + i]) : 0.0f;
    \\      sum[m] += value;
    \\      local[m][i] = value;
    \\    }
    \\    }
    \\  }
    \\  for (int r = 0; r < 2; ++r) {
    \\    const int output = output0 + r;
    \\    const int group = output * (K / 128) + k / 128 + lane / (128 / V);
    \\    const float scale = float(scales[group]);
    \\    const float bias = float(biases[group]);
    \\    float quant[8];
    \\    if (BITS == 8) for (int i = 0; i < 8; ++i) quant[i] = float(codes[size_t(output) * K + k + lane * 8 + i]);
    \\    float coeff[12];
    \\    float accum5[R];
    \\    // A5 hoists one pack at a time (all 24 coefficients ran slower than serial rows); rows add in qdot order.
    \\    if (BITS == 5) {
    \\      const device uint8_t* packed = codes + size_t(output)*(K*5/8) + (k+lane*16)*5/8;
    \\      for (int m = 0; m < R; ++m) accum5[m] = 0.0f;
    \\      for (int pack = 0; pack < 2; ++pack) {
    \\        const device uint8_t* q = packed + pack*5;
    \\        coeff[0] = float(q[0]&0x1f);
    \\        coeff[1] = float(q[0]&0xe0);
    \\        coeff[2] = float(q[1]&0x03);
    \\        coeff[3] = float(q[1]&0x7c);
    \\        coeff[4] = float(q[1]&0x80);
    \\        coeff[5] = float(q[2]&0x0f);
    \\        coeff[6] = float(q[2]&0xf0);
    \\        coeff[7] = float(q[3]&0x01);
    \\        coeff[8] = float(q[3]&0x3e);
    \\        coeff[9] = float(q[3]&0xc0);
    \\        coeff[10] = float(q[4]&0x07);
    \\        coeff[11] = float(q[4]&0xf8);
    \\        const int i = pack*8;
    \\        for (int m = 0; m < R; ++m) {
    \\          accum5[m] += coeff[0]*local[m][i];
    \\          accum5[m] += coeff[1]*local[m][i+1];
    \\          accum5[m] += coeff[2]*(local[m][i+1]*256.0f);
    \\          accum5[m] += coeff[3]*local[m][i+2];
    \\          accum5[m] += coeff[4]*local[m][i+3];
    \\          accum5[m] += coeff[5]*(local[m][i+3]*256.0f);
    \\          accum5[m] += coeff[6]*local[m][i+4];
    \\          accum5[m] += coeff[7]*(local[m][i+4]*256.0f);
    \\          accum5[m] += coeff[8]*local[m][i+5];
    \\          accum5[m] += coeff[9]*local[m][i+6];
    \\          accum5[m] += coeff[10]*(local[m][i+6]*256.0f);
    \\          accum5[m] += coeff[11]*local[m][i+7];
    \\        }
    \\      }
    \\    }
    \\    if (BITS == 6) {
    \\      const device uint8_t* packed = codes + size_t(output)*(K*3/4) + (k+lane*8)*3/4;
    \\      for (int pack = 0; pack < 2; ++pack) {
    \\        const device uint8_t* q = packed + pack*3;
    \\        const int c = pack*6;
    \\        coeff[c] = float(q[0]&0x3f);
    \\        coeff[c+1] = float(q[0]&0xc0);
    \\        coeff[c+2] = float(q[1]&0x0f);
    \\        coeff[c+3] = float(q[1]&0xf0);
    \\        coeff[c+4] = float(q[2]&0x03);
    \\        coeff[c+5] = float(q[2]&0xfc);
    \\      }
    \\    }
    \\    for (int m = 0; m < R; ++m) {
    \\      float accum = 0.0f;
    \\      if (BITS == 5) {
    \\        accum = accum5[m];
    \\      } else if (BITS == 6) {
    \\        for (int pack = 0; pack < 2; ++pack) {
    \\          const int i = pack*4, c = pack*6;
    \\          accum += coeff[c]*local[m][i];
    \\          accum += coeff[c+1]*local[m][i+1];
    \\          accum += coeff[c+2]*(local[m][i+1]*256.0f);
    \\          accum += coeff[c+3]*local[m][i+2];
    \\          accum += coeff[c+4]*(local[m][i+2]*256.0f);
    \\          accum += coeff[c+5]*local[m][i+3];
    \\        }
    \\      } else for (int i = 0; i < 8; ++i) accum += local[m][i] * quant[i];
    \\      result[m][r] += scale * accum + sum[m] * bias;
    \\    }
    \\  }
    \\}
    \\for (int m = 0; m < R; ++m) for (int r = 0; r < 2; ++r) {
    \\  const float value = simd_sum(result[m][r]);
    \\  if (lane == 0 && token0 + m < M) y[(token0 + m) * N + output0 + r] = bfloat(value);
    \\}
;
// The MLA value bank adds a head axis; its per-row arithmetic is identical.
fn replace(comptime source: []const u8, comptime old: []const u8, comptime value: []const u8) [:0]const u8 {
    @setEvalBranchQuota(1000000);
    const at = std.mem.indexOf(u8, source, old) orelse return source ++ "";
    return source[0..at] ++ value ++ replace(source[at + old.len ..], old, value);
}
const HEAD_SOURCE: [:0]const u8 = blk: {
    var body = replace(SOURCE, "int(simdgroup_index_in_threadgroup) * 2", "int(simdgroup_index_in_threadgroup) * 4");
    body = replace(body, "result[R][2]", "result[R][4]");
    body = replace(body, "r < 2", "r < 4");
    body = replace(body, "const int token0 = 0;", "const int token0 = 0;\nconst int head = int(threadgroup_position_in_grid.z);");
    body = replace(body, "reinterpret_cast<const device uint8_t*>(w);", "reinterpret_cast<const device uint8_t*>(w) + size_t(head)*N*K*BITS/8;");
    body = replace(body, "(token0+m)*K", "((token0+m)*64+head)*K");
    body = replace(body, "(token0 + m) * K", "((token0 + m)*64+head) * K");
    body = replace(body, "const int group = output *", "const int group = head*N*(K/128) + output *");
    body = replace(body, "(token0 + m) * N", "((token0 + m)*64+head) * N");
    break :blk body;
};
// Preserve qmv_fast's BF16 sum boundaries and power-of-two scaling once per input.
const INPUT_PREP_SOURCE =
    \\const uint group=thread_position_in_grid.x;
    \\constexpr uint V=BITS==5?16:8;
    \\if(group>=uint(M*K/V))return;
    \\const uint at=group*V;
    \\float sum=0.0f;
    \\if(BITS==5) for(uint i=0;i<16;i+=8) {
    \\ sum+=x[at+i]+x[at+i+1]+x[at+i+2]+x[at+i+3]+x[at+i+4]+x[at+i+5]+x[at+i+6]+x[at+i+7];
    \\ px[at+i]=float(x[at+i]);
    \\ px[at+i+1]=float(x[at+i+1])/32.0f;
    \\ px[at+i+2]=float(x[at+i+2])/4.0f;
    \\ px[at+i+3]=float(x[at+i+3])/128.0f;
    \\ px[at+i+4]=float(x[at+i+4])/16.0f;
    \\ px[at+i+5]=float(x[at+i+5])/2.0f;
    \\ px[at+i+6]=float(x[at+i+6])/64.0f;
    \\ px[at+i+7]=float(x[at+i+7])/8.0f;
    \\} else for(uint i=0;i<8;i+=4) {
    \\ sum+=x[at+i]+x[at+i+1]+x[at+i+2]+x[at+i+3];
    \\ px[at+i]=float(x[at+i]);
    \\ px[at+i+1]=float(x[at+i+1])/64.0f;
    \\ px[at+i+2]=float(x[at+i+2])/16.0f;
    \\ px[at+i+3]=float(x[at+i+3])/4.0f;
    \\}
    \\ps[group]=sum;
;
const PREPARED_SOURCE: [:0]const u8 = blk: {
    const start = std.mem.indexOf(u8, SOURCE, "  for (int m = 0; m < R; ++m) {\n    sum[m]").?;
    const end = std.mem.indexOfPos(u8, SOURCE, start, "  for (int r = 0; r < 2;").?;
    break :blk SOURCE[0..start] ++
        "  for(int m=0;m<R;++m){sum[m]=ps[m*(K/V)+k/V+lane];for(int i=0;i<V;++i)local[m][i]=px[m*K+k+lane*V+i];}\n" ++ SOURCE[end..];
};
var prepare_kernel: ?mlx.mlx_fast_metal_kernel = null;
const PrepConfig = struct { k: c_int, bits: c_int, config: mlx.mlx_fast_metal_kernel_config };
var prepare_configs: [8]?PrepConfig = @splat(null);
const Prepared = struct {
    scaled: Arr,
    sums: Arr,
    fn deinit(self: Prepared) void {
        _ = mlx.mlx_array_free(self.scaled);
        _ = mlx.mlx_array_free(self.sums);
    }
};
fn prepare(stream: mlx.mlx_stream, x: Arr, k: c_int, bits: c_int) !Prepared {
    if (prepare_kernel == null) {
        const iv = mlx.mlx_vector_string_new_data(&.{"x"}, 1);
        defer _ = mlx.mlx_vector_string_free(iv);
        const ov = mlx.mlx_vector_string_new_data(&.{ "px", "ps" }, 2);
        defer _ = mlx.mlx_vector_string_free(ov);
        const kernel = mlx.mlx_fast_metal_kernel_new("sushi_a6_prepare_three", iv, ov, INPUT_PREP_SOURCE, "", true, false);
        if (kernel.ctx == null) return error.MetalKernelCompileFailed;
        prepare_kernel = kernel;
    }
    var cached: ?mlx.mlx_fast_metal_kernel_config = null;
    for (prepare_configs) |entry| if (entry) |v| {
        if (v.k == k and v.bits == bits) {
            cached = v.config;
            break;
        }
    };
    const config = cached orelse mlx.mlx_fast_metal_kernel_config_new();
    var retained = cached != null;
    defer if (!retained) {
        _ = mlx.mlx_fast_metal_kernel_config_free(config);
    };
    if (cached == null) {
        try mlx.check(mlx.mlx_fast_metal_kernel_config_add_output_arg(config, &.{ 1, 3, k }, 3, .float32));
        const lane_values: c_int = if (bits == 5) 16 else 8;
        try mlx.check(mlx.mlx_fast_metal_kernel_config_add_output_arg(config, &.{ 1, 3, @divExact(k, lane_values) }, 3, .float32));
        try mlx.check(mlx.mlx_fast_metal_kernel_config_set_grid(config, 3 * @divExact(k, lane_values), 1, 1));
        try mlx.check(mlx.mlx_fast_metal_kernel_config_set_thread_group(config, 256, 1, 1));
        try mlx.check(mlx.mlx_fast_metal_kernel_config_add_template_arg_int(config, "M", 3));
        try mlx.check(mlx.mlx_fast_metal_kernel_config_add_template_arg_int(config, "K", k));
        try mlx.check(mlx.mlx_fast_metal_kernel_config_add_template_arg_int(config, "BITS", bits));
        for (&prepare_configs) |*entry| if (entry.* == null) {
            entry.* = .{ .k = k, .bits = bits, .config = config };
            retained = true;
            break;
        };
    }
    const iv = mlx.mlx_vector_array_new_value(x);
    defer _ = mlx.mlx_vector_array_free(iv);
    var ov = mlx.mlx_vector_array_new();
    defer _ = mlx.mlx_vector_array_free(ov);
    try mlx.check(mlx.mlx_fast_metal_kernel_apply(&ov, prepare_kernel.?, iv, config, stream));
    var result = Prepared{ .scaled = mlx.mlx_array_new(), .sums = mlx.mlx_array_new() };
    errdefer result.deinit();
    try mlx.check(mlx.mlx_vector_array_get(&result.scaled, ov, 0));
    try mlx.check(mlx.mlx_vector_array_get(&result.sums, ov, 1));
    return result;
}

var dispatch_count: usize = 0;
pub fn dispatchCount() usize {
    return dispatch_count;
}
pub fn resetDispatchCount() void {
    dispatch_count = 0;
}
var kernels: [3]?mlx.mlx_fast_metal_kernel = @splat(null);
const Key = struct { m: c_int, n: c_int, k: c_int, bits: c_int, headed: bool, prepared: bool };
const Cached = struct { key: Key, config: mlx.mlx_fast_metal_kernel_config };
var configs: [32]?Cached = @splat(null);

fn rowMajorReady(a: Arr) !bool {
    if (a.ctx == null) return false;
    const shape = mlx.getShape(a);
    if (shape.len != 2 and shape.len != 3) return false;
    const strides = mlx.mlx_array_strides(a);
    const last = shape.len - 1;
    if (strides[last] != 1 or strides[last - 1] != shape[last]) return false;
    if (shape.len == 3 and strides[0] != @as(i64, shape[1]) * shape[2]) return false;
    var available = false;
    try mlx.check(mlx._mlx_array_is_available(&available, a));
    return available;
}

pub fn project(stream: mlx.mlx_stream, x: Arr, linear: Linear) !?Arr {
    if (!mlx.streamIsGpu(stream) or x.ctx == null or linear.w.ctx == null or linear.scales.ctx == null or linear.biases.ctx == null) return null;
    const sh = mlx.getShape(x);
    const ws = mlx.getShape(linear.w);
    const headed = sh.len == 4;
    if (headed) {
        if (!std.mem.eql(c_int, sh, &.{ 3, 64, 1, 512 }) or !(std.mem.eql(c_int, ws, &.{ 64, 256, 96 }) or std.mem.eql(c_int, ws, &.{ 64, 256, 80 }))) return null;
    } else if (sh.len != 3 or sh[0] != 1 or (sh[1] != 3 and sh[1] != 4) or sh[2] < 256 or @mod(sh[2], 256) != 0 or ws.len != 2 or ws[0] < 8 or @mod(ws[0], 8) != 0) return null;
    const k = sh[sh.len - 1];
    const n = ws[ws.len - 2];
    const bits: c_int = if (@as(i64, ws[ws.len - 1]) * 16 == @as(i64, k) * 3) 6 else if (@mod(k, 512) == 0 and @as(i64, ws[ws.len - 1]) * 32 == @as(i64, k) * 5) 5 else return null;
    if (mlx.mlx_array_dtype(x) != .bfloat16 or mlx.mlx_array_dtype(linear.w) != .uint32 or !(try rowMajorReady(linear.w))) return null;
    const grid_shape = [_]c_int{ 64, n, @divExact(k, 128) };
    for ([_]Arr{ linear.scales, linear.biases }) |grid| {
        if (mlx.mlx_array_dtype(grid) != .bfloat16 or !std.mem.eql(c_int, if (headed) &grid_shape else grid_shape[1..], mlx.getShape(grid)) or !(try rowMajorReady(grid))) return null;
    }
    const prepared = if (@import("glm5_model.zig").naxArms() and !headed and sh[1] == 3 and n >= 4096 and k >= 4096) try prepare(stream, x, k, bits) else null;
    defer if (prepared) |value| value.deinit();
    const kernel = &kernels[if (prepared != null) @as(usize, 2) else @intFromBool(headed)];
    if (kernel.* == null) {
        const ins = [_][*:0]const u8{ "x", "w", "scales", "biases", "px", "ps" };
        const outs = [_][*:0]const u8{"y"};
        const iv = mlx.mlx_vector_string_new_data(&ins, if (prepared != null) 6 else 4);
        defer _ = mlx.mlx_vector_string_free(iv);
        const ov = mlx.mlx_vector_string_new_data(&outs, outs.len);
        defer _ = mlx.mlx_vector_string_free(ov);
        kernel.* = mlx.mlx_fast_metal_kernel_new(if (prepared != null) "sushi_glm_a6_prepared" else if (headed) "sushi_glm_value_three_rows" else "sushi_glm_dflash_affine6_hoisted", iv, ov, if (prepared != null) PREPARED_SOURCE else if (headed) HEAD_SOURCE else SOURCE, "", true, false);
        if (kernel.*.?.ctx == null) {
            kernel.* = null;
            return error.MetalKernelCompileFailed;
        }
    }
    const key = Key{ .m = if (headed) sh[0] else sh[1], .n = n, .k = k, .bits = bits, .headed = headed, .prepared = prepared != null };
    var cached: ?mlx.mlx_fast_metal_kernel_config = null;
    for (configs) |item| if (item) |entry| if (std.meta.eql(key, entry.key)) {
        cached = entry.config;
        break;
    };
    const config = cached orelse mlx.mlx_fast_metal_kernel_config_new();
    var retained = cached != null;
    defer if (!retained) {
        _ = mlx.mlx_fast_metal_kernel_config_free(config);
    };
    if (cached == null) {
        const tile: c_int = if (key.m < 4) key.m else 4;
        const output_shape: []const c_int = if (headed) &.{ key.m, 64, 1, key.n } else &.{ 1, key.m, key.n };
        const threads: c_int = if (headed) 64 else 128;
        try mlx.check(mlx.mlx_fast_metal_kernel_config_add_output_arg(config, output_shape.ptr, output_shape.len, .bfloat16));
        try mlx.check(mlx.mlx_fast_metal_kernel_config_set_grid(config, @divExact(key.n, 8) * threads, @divTrunc(key.m + tile - 1, tile), if (headed) 64 else 1));
        try mlx.check(mlx.mlx_fast_metal_kernel_config_set_thread_group(config, threads, 1, 1));
        try mlx.check(mlx.mlx_fast_metal_kernel_config_add_template_arg_int(config, "M", key.m));
        try mlx.check(mlx.mlx_fast_metal_kernel_config_add_template_arg_int(config, "N", key.n));
        try mlx.check(mlx.mlx_fast_metal_kernel_config_add_template_arg_int(config, "K", key.k));
        try mlx.check(mlx.mlx_fast_metal_kernel_config_add_template_arg_int(config, "R", tile));
        try mlx.check(mlx.mlx_fast_metal_kernel_config_add_template_arg_int(config, "BITS", bits));
        for (&configs) |*item| if (item.* == null) {
            item.* = .{ .key = key, .config = config };
            retained = true;
            break;
        };
    }
    const arrays = [_]Arr{ x, linear.w, linear.scales, linear.biases, if (prepared) |v| v.scaled else .{ .ctx = null }, if (prepared) |v| v.sums else .{ .ctx = null } };
    const iv = mlx.mlx_vector_array_new_data(&arrays, if (prepared != null) 6 else 4);
    defer _ = mlx.mlx_vector_array_free(iv);
    var ov = mlx.mlx_vector_array_new();
    defer _ = mlx.mlx_vector_array_free(ov);
    try mlx.check(mlx.mlx_fast_metal_kernel_apply(&ov, kernel.*.?, iv, config, stream));
    var output = mlx.mlx_array_new();
    errdefer _ = mlx.mlx_array_free(output);
    try mlx.check(mlx.mlx_vector_array_get(&output, ov, 0));
    dispatch_count += 1;
    @import("glm5_decode.zig").logEngaged(.hoist, bits);
    return output;
}
