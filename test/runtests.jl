#!/usr/bin/julia -f

import FunctionWrappers
import FunctionWrappers: FunctionWrapper
using Test

struct CallbackF64
    f::FunctionWrapper{Float64,Tuple{Int}}
end
(cb::CallbackF64)(v) = cb.f(v)
gen_closure(x) = y->x + y

@testset "As field" begin
    f1 = @inferred CallbackF64(identity)
    f2 = @inferred CallbackF64(sin)
    f3 = @inferred CallbackF64(gen_closure(2))
    @test typeof(f1) == typeof(f2) == typeof(f3)
    @test @inferred(f1(1)) === 1.0
    @test @inferred(f2(1)) === sin(1)
    @test @inferred(f3(1)) === 3.0
end

const F64AnyFunc = FunctionWrapper{Float64,Tuple{Any}}

@testset "Any input" begin
    f1 = @inferred F64AnyFunc(identity)
    f2 = @inferred F64AnyFunc(gen_closure(2))
    @test typeof(f1) === typeof(f2)
    @test @inferred(f1(1)) === 1.0
    @test @inferred(f1(1.0)) === 1.0
    @test @inferred(f1(1f0)) === 1.0
    @test @inferred(f2(1)) === 3.0
end

const F64F64Func = FunctionWrapper{Float64,Tuple{Float64}}

@testset "Convert" begin
    f1 = @inferred F64F64Func(sin)
    f2 = @inferred F64F64Func(f1)
    f3 = @inferred convert(F64F64Func, f1)
    @test f1 === f2
    @test f1 === f3
end

const NumberAnyFunc = FunctionWrapper{Number,Tuple{Any}}

@testset "Abstract Return" begin
    @test NumberAnyFunc(sin)(1) === sin(1)
    @test NumberAnyFunc(identity)(1) === 1
end

@testset "Precompile" begin
    @test FunctionWrappers.identityAnyAny(1) === 1
end

mutable struct Counter
    n::Int
end
(c::Counter)(x::Int) = (c.n += x; c.n)

@testset "Re-initialize null pointers" begin
    c = Counter(10)
    for (f, x, y) in ((FunctionWrapper{Int,Tuple{Int}}(c), 1, 11),
                      (F64F64Func(gen_closure(2.0)), 1.0, 3.0))
        f.ptr = C_NULL
        f.objptr = C_NULL
        @test f(x) === y
        @test f.ptr != C_NULL
    end
    @test c.n == 11
end

@static if VERSION >= v"1.12"
    # `--trim` verification accepts a run-time dispatch only if it is inferred as never returning.
    callee(f::GlobalRef) = getfield(f.mod, f.name)
    callee(f) = f
    @testset "Run-time dispatch in reinit_wrapper never returns" begin
        ci = first(code_typed(FunctionWrappers.reinit_wrapper, (F64F64Func,)))[1]
        dynamic = [i for (i, s) in pairs(ci.code)
                   if Meta.isexpr(s, :call) && !(callee(s.args[1]) isa Core.Builtin)]
        @test !isempty(dynamic)
        @test all(i -> ci.ssavaluetypes[i] === Union{}, dynamic)
    end
end

struct SingletonType
end

@testset "Void" begin
    identityVoidVoid = FunctionWrapper{Cvoid,Tuple{Cvoid}}(identity)
    @test identityVoidVoid(nothing) === nothing
    f1 = (a, b)->b
    fIntVoidInt = FunctionWrapper{Int,Tuple{Cvoid,Int}}(f1)
    @test fIntVoidInt(nothing, 1) === 1

    # Void return type ignores actual value
    identityVoidInt = FunctionWrapper{Cvoid,Tuple{Int}}(identity)
    @test identityVoidInt(1) === nothing

    # Void return type ignores actual value
    identitySInt = FunctionWrapper{SingletonType,Tuple{Int}}(identity)
    @test_throws MethodError identitySInt(1)
end

@testset "Convert" begin
    identityIntF64 = FunctionWrapper{Int,Tuple{Float64}}(identity)
    @test identityIntF64(1.0) === 1
    @test identityIntF64(1) === 1

    identityF64Int = FunctionWrapper{Float64,Tuple{Int}}(identity)
    @test identityF64Int(1) === 1.0
    @test identityF64Int(1.0) === 1.0
end

struct InlineRefStruct
    x::Vector{Int}
end

@testset "Inline struct with Ref" begin
    f = @inferred FunctionWrapper{InlineRefStruct,Tuple{InlineRefStruct}}(identity)
    v = InlineRefStruct([1, 2, 3])
    @test @inferred(f(v)) === v
end

struct Shift
    c::Float64
end
(s::Shift)(x::Float64) = x - s.c
call_local_wrapper(x) = FunctionWrapper{Float64,Tuple{Float64}}(Shift(x))(2x)

@testset "Wrapper built and called in the same function" begin
    @test call_local_wrapper(1.5) === 1.5
end

@testset "FunctionWrapper is public API" begin
    # Public, but deliberately not exported: `using FunctionWrappers` must not
    # introduce the name into the caller's namespace, since `FunctionWrapper` is a
    # common enough identifier to collide.
    @test !Base.isexported(FunctionWrappers, :FunctionWrapper)
    @static if VERSION >= v"1.11"
        @test Base.ispublic(FunctionWrappers, :FunctionWrapper)
        @test :FunctionWrapper in names(FunctionWrappers)
    end
end
