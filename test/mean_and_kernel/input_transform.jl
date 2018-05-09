using Stheno: ConstantMean, ITMean, ITKernel, getobs

@testset "input_transform" begin

    # Test ITMean.
    let
        rng, N, D = MersenneTwister(123456), 10, 2
        μ, f, X = ConstantMean(randn(rng)), x->sum(abs2, x), randn(rng, D, N)
        μf = ITMean(μ, f)

        @test μf(getobs(X, 1)) == (μ ∘ f)(getobs(X, 1))
        mean_function_tests(μf, X)
    end

    # Test ITKernel.
    let
        rng, N, N′, D = MersenneTwister(123456), 10, 11, 2
        k, f = EQ(), x->sum(abs2, x)
        X0, X1, X2 = randn(rng, D, N), randn(rng, D, N), randn(rng, D, N′)
        kf = ITKernel(k, f)

        @test kf(getobs(X0, 1), getobs(X1, 1)) == k(f(getobs(X0, 1)), f(getobs(X1, 1)))
        kernel_tests(kf, X0, X1, X2)
    end

    # Test convenience code.
    let
        rng, N, N′, D = MersenneTwister(123456), 10, 11, 2
        m, k = ConstantMean(randn(rng)), EQ()
        X0, X1, X2 = randn(rng, D, N), randn(rng, D, N), randn(rng, D, N′)
        m1, k1 = pick_dims(m, 1), pick_dims(k, 1)

        @test m1(getobs(X0, 1)) == m(getobs(X0, 1)[1])
        @test k1(getobs(X0, 1), getobs(X0, 2)) == k(getobs(X0, 1)[1], getobs(X0, 2)[1])
        mean_function_tests(m1, X0)
        kernel_tests(k1, X0, X1, X2)

        # mean_function_tests(periodic(m, 0.1), X0)
        # kernel_tests(periodic(k, 0.1), X0, X1, X2)
    end

end
