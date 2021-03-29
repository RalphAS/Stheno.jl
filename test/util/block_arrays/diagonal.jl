using Stheno: block_diagonal, BlockDiagonal, blocksizes

function general_BlockDiagonal_tests(rng, blocks)
    d = block_diagonal(blocks)
    Ps, Qs = size.(blocks, 1), size.(blocks, 2)

    @testset "general" begin
        @test blocksizes(d, 1) == Ps
        @test blocksizes(d, 2) == Qs

        @test view(d, Block(1, 1)) == blocks[1]
        @test view(d, Block(2, 2)) == blocks[2]
        @test view(d, Block(1, 2)) == zeros(Ps[1], Qs[2])
        @test view(d, Block(2, 1)) == zeros(Ps[2], Qs[1])

        @test d[Block(1, 1)] == view(d, Block(1, 1))
    end
end

function BlockDiagonal_mul_tests(rng, blocks)
    D, Ps = block_diagonal(blocks), size.(blocks, 1)
    Dmat = Matrix(D)

    U = UpperTriangular(D)

    xs, ys = [randn(rng, P) for P in Ps], [randn(rng, P) for P in Ps]
    y, x = mortar(ys), mortar(xs)

    # Matrix-Vector product
    @test mul!(y, D, x) ≈ Dmat * Vector(x)
    @test mul!(y, D, x) == D * x
    @test mul!(y, U, x) ≈ Matrix(U) * Vector(x)
    @test mul!(y, U, x) == U * x

    Qs = [3, 4]
    X = mortar([randn(rng, P, Q) for P in Ps, Q in Qs])
    Y = mortar([randn(rng, P, Q) for P in Ps, Q in Qs])

    # Matrix-Matrix product
    @test mul!(Y, D, X) ≈ Dmat * X
    @test mul!(Y, U, X) ≈ Matrix(U) * Matrix(X)
    @test mul!(Y, D, X) == D * X
    @test mul!(Y, U, X) == U * X
end

function BlockDiagonal_chol_tests(rng, blocks)

    D, Ps = block_diagonal(blocks), size.(blocks, 1)
    Dmat = Matrix(D)

    C, Cmat = cholesky(D), cholesky(Dmat)

    @test C.U ≈ Cmat.U
    @test logdet(C) ≈ logdet(Cmat)

    Csym = cholesky(Symmetric(D))
    @test C.U ≈ Csym.U

    # Test backprop for accessing `U`.
    U_diag, back_diag = Zygote.pullback(D->cholesky(D).U, D)
    U_dens, back_dens = Zygote.pullback(D->cholesky(D).U, Matrix(D))

    @test U_diag ≈ U_dens

    Ū = block_diagonal([randn(rng, P, P) for P in Ps])
    D̄_diag = first(back_diag(Ū))
    D̄_dens = first(back_dens(Matrix(Ū)))
    @test Matrix(D̄_diag) ≈ D̄_dens
    @test D̄_diag isa BlockDiagonal

    # Test backprop for logdet of a Cholesky.
    l_diag, l_back_diag = Zygote.pullback(D->logdet(cholesky(D)), D)
    l_dens, l_back_dens = Zygote.pullback(D->logdet(cholesky(D)), Matrix(D))

    @test l_diag ≈ l_dens

    l̄ = randn(rng)
    D̄_diag = first(l_back_diag(l̄))
    D̄_dens = first(l_back_dens(l̄))
    @test Matrix(D̄_diag) ≈ D̄_dens
    @test D̄_diag isa BlockDiagonal
end

function BlockDiagonal_add_tests(rng, blks; grad=true)

    D = block_diagonal(blks)
    Dmat = Matrix(D)
    A = randn(rng, size(D))

    A_copy = copy(A)
    C = A_copy + D
    @test A_copy == A
    @test C == A + Dmat

    if grad == true
        @assert length(blks) == 2
        adjoint_test(
            (A, b1, b2)->A + block_diagonal([b1, b2]),
            randn(rng, size(A)), A, blks[1], blks[2],
        )
    end
end

@timedtestset "BlockDiagonal" begin
    @timedtestset "Matrix" begin
        rng, Ps, Qs = MersenneTwister(123456), [2, 3], [4, 5]
        vs = [randn(rng, Ps[1], Qs[1]), randn(rng, Ps[2], Qs[2])]
        general_BlockDiagonal_tests(rng, vs)

        As = [randn(rng, Ps[n], Ps[n]) for n in eachindex(Ps)]
        blks = [As[n] * As[n]' + I for n in eachindex(As)]
        BlockDiagonal_mul_tests(rng, blks)
        BlockDiagonal_mul_tests(rng, UpperTriangular.(blks))
        BlockDiagonal_mul_tests(rng, Hermitian.(blks))
        BlockDiagonal_mul_tests(rng, Symmetric.(blks))
        BlockDiagonal_chol_tests(rng, blks)
        BlockDiagonal_add_tests(rng, blks; grad=false)
    end
    @timedtestset "Diagonal{T, <:Vector{T}}" begin
        rng, Ps = MersenneTwister(123456), [2, 3]
        vs = [Diagonal(randn(rng, Ps[n])) for n in eachindex(Ps)]
        general_BlockDiagonal_tests(rng, vs)

        blocks = [Diagonal(ones(P) + exp.(randn(rng, P))) for P in Ps]
        BlockDiagonal_add_tests(rng, blocks; grad=false)
        @timedtestset "cholesky" begin
            x, ȳ = randn(rng, sum(Ps)), randn(rng, sum(Ps))
            adjoint_test((X, blks)->cholesky(block_diagonal(blks)).U \ X, ȳ, x, blocks)

            X, Ȳ = randn(rng, sum(Ps), 7), randn(rng, sum(Ps), 7)
            adjoint_test((X, blks)->cholesky(block_diagonal(blks)).U \ X, Ȳ, X, blocks)
            adjoint_test(blks->logdet(cholesky(block_diagonal(blks))), randn(rng), blocks)
        end
    end
    @timedtestset "Negation" begin
        rng, Ps = MersenneTwister(123456), [4, 5, 6, 7]
        A = block_diagonal([randn(rng, P, P) for P in Ps])

        @test Matrix(-A) == -Matrix(A)
        @test -A isa BlockDiagonal

        Y_diag, back_diag = Zygote.pullback(-, A)
        Y_dens, back_dens = Zygote.pullback(-, Matrix(A))

        Ȳ = block_diagonal([randn(rng, P, P) for P in Ps])
        @test Y_diag == -A
        @test Matrix(first(back_diag(Ȳ))) == first(back_dens(Matrix(Ȳ)))
        @test first(back_diag(Ȳ)) isa BlockDiagonal
    end
    @timedtestset "adjoint" begin
        rng, Ps = MersenneTwister(123456), [4, 5, 6]
        A = block_diagonal([randn(rng, P, P) for P in Ps])

        @test Matrix(A') == Matrix(A)'
        @test A' isa BlockDiagonal

        Y, back = Zygote.pullback(adjoint, A)
        Y_dens, back_dens = Zygote.pullback(adjoint, Matrix(A))
        Ȳ = block_diagonal([randn(rng, P, P) for P in Ps])
        @test Y == A'
        @test Matrix(first(back(Ȳ))) == first(back_dens(Matrix(Ȳ)))
        @test first(back(Ȳ)) isa BlockDiagonal
    end
    @timedtestset "transpose" begin
        rng, Ps = MersenneTwister(123456), [4, 5, 6]
        A = block_diagonal([randn(rng, P, P) for P in Ps])

        @test Matrix(transpose(A)) == transpose(Matrix(A))
        @test transpose(A) isa BlockDiagonal

        Y, back = Zygote.pullback(transpose, A)
        Y_dens, back_dens = Zygote.pullback(transpose, Matrix(A))
        Ȳ = block_diagonal([randn(rng, P, P) for P in Ps])
        @test Y == transpose(A)
        @test Matrix(first(back(Ȳ))) == first(back_dens(Matrix(Ȳ)))
        @test first(back(Ȳ)) isa BlockDiagonal
    end
    @timedtestset "UpperTriangular" begin
        rng, Ps = MersenneTwister(123456), [4, 5, 6]
        A = block_diagonal([randn(rng, P, P) for P in Ps])

        @test Matrix(UpperTriangular(A)) == UpperTriangular(Matrix(A))
        @test UpperTriangular(A) isa BlockDiagonal

        B_diag, back_diag = Zygote.pullback(UpperTriangular, A)
        B_dens, back_dens = Zygote.pullback(UpperTriangular, Matrix(A))
        @test Matrix(B_diag) == B_dens

        B̄ = block_diagonal([randn(rng, P, P) for P in Ps])
        Ā_diag, Ā_dens = first(back_diag(B̄)), first(back_dens(Matrix(B̄)))
        @test Ā_diag == Ā_dens
        @test Ā_diag isa BlockDiagonal
    end
    @timedtestset "Symmetric" begin
        rng, Ps = MersenneTwister(123456), [4, 5, 6]
        A = block_diagonal([randn(rng, P, P) for P in Ps])
        S = Symmetric(A)
        @test S == Symmetric(Matrix(A))
        @test S isa BlockDiagonal

        S_diag, back_diag = Zygote.pullback(Symmetric, A)
        S_dens, back_dens = Zygote.pullback(Symmetric, Matrix(A))
        @test S_diag ≈ S_dens
    end
    @timedtestset "BlockDiagonal * BlockDiagonal" begin
        rng, Ps = MersenneTwister(123456), [4, 5, 6]
        A = block_diagonal([randn(rng, P, P) for P in Ps])
        B = block_diagonal([randn(rng, P, P) for P in Ps])

        @test Matrix(A * B) ≈ Matrix(A) * Matrix(B)
        @test A * B isa BlockDiagonal

        Y_diag, back_diag = Zygote.pullback(*, A, B)
        Y_dens, back_dens = Zygote.pullback(*, Matrix(A), Matrix(B))

        Ȳ = block_diagonal([randn(rng, P, P) for P in Ps])
        @test Y_diag == A * B

        Ā_diag, B̄_diag = back_diag(Ȳ)
        Ā_dens, B̄_dens = back_dens(Matrix(Ȳ))

        @test Matrix(Ā_diag) ≈ Ā_dens
        @test Matrix(B̄_diag) ≈ B̄_dens

        @test Ā_diag isa BlockDiagonal
        @test B̄_diag isa BlockDiagonal
    end
    @timedtestset "BlockDiagonal * Matrix" begin
        rng, Ps, Q = MersenneTwister(123456), [4, 5, 6], 11
        A = block_diagonal([randn(rng, P, P) for P in Ps])
        B = randn(rng, sum(Ps), Q)
        @test Matrix(A * B) ≈ Matrix(A) * B
        @test Matrix(A * collect(B')') ≈ Matrix(A) * B

        Y_diag, back_diag = Zygote.pullback(*, A, B)
        Y_dens, back_dens = Zygote.pullback(*, Matrix(A), B)
        @test Y_diag ≈ Y_dens

        Ȳ = randn(rng, sum(Ps), Q)
        Ā_diag, B̄_diag = back_diag(Ȳ)
        Ā_dens, B̄_dens = back_dens(Ȳ)
        @test Matrix(Ā_diag) ≈ Ā_dens
        @test B̄_diag ≈ B̄_dens
        @test_broken Ā_diag isa BlockDiagonal
    end
    @timedtestset "BlockDiagonal * Vector" begin
        rng, Ps = MersenneTwister(123456), [4, 5, 6]
        A = block_diagonal([randn(rng, P, P) for P in Ps])
        x = randn(rng, sum(Ps))
        @test Vector(A * x) ≈ Matrix(A) * x

        Y_diag, back_diag = Zygote.pullback(*, A, x)
        Y_dens, back_dens = Zygote.pullback(*, Matrix(A), x)
        @test Y_diag ≈ Y_dens

        ȳ = randn(rng, sum(Ps))
        Ā_diag, x̄_diag = back_diag(ȳ)
        Ā_dens, x̄_dens = back_dens(ȳ)
        @test Matrix(Ā_diag) ≈ Ā_dens
        @test x̄_diag ≈ x̄_dens
        @test_broken Ā_diag isa BlockDiagonal
    end
    @timedtestset "ldiv(BlockDiagonal, Matrix)" begin
        rng, Ps, Q = MersenneTwister(123456), [4, 5, 6], 11
        A = block_diagonal([randn(rng, P, P) for P in Ps])
        B = randn(rng, sum(Ps), Q)
        @test Matrix(A \ B) ≈ Matrix(A) \ B

        Y_diag, back_diag = Zygote.pullback(\, A, B)
        Y_dens, back_dens = Zygote.pullback(\, Matrix(A), B)
        @test Y_diag ≈ Y_dens

        Ȳ = randn(rng, sum(Ps), Q)
        Ā_diag, B̄_diag = back_diag(Ȳ)
        Ā_dens, B̄_dens = back_dens(Ȳ)
        @test_broken Matrix(Ā_diag) ≈ Ā_dens # we're not checking the right bits of the matrix here
        @test B̄_diag ≈ B̄_dens
        @test Ā_diag isa BlockDiagonal
        @test blocksizes(Ā_diag, 1) == blocksizes(A, 1)
        @test blocksizes(Ā_diag, 2) == blocksizes(A, 2)
    end
    @timedtestset "ldiv(BlockDiagonal, Vector)" begin
        rng, Ps = MersenneTwister(123456), [4, 5, 6]
        A = block_diagonal([randn(rng, P, P) for P in Ps])
        B = randn(rng, sum(Ps))
        @test Vector(A \ B) ≈ Matrix(A) \ B

        Y_diag, back_diag = Zygote.pullback(\, A, B)
        Y_dens, back_dens = Zygote.pullback(\, Matrix(A), B)
        @test Y_diag ≈ Y_dens

        Ȳ = randn(rng, sum(Ps))
        Ā_diag, B̄_diag = back_diag(Ȳ)
        Ā_dens, B̄_dens = back_dens(Ȳ)
        @test_broken Matrix(Ā_diag) ≈ Ā_dens # we're not checking the right bits of the matrix here
        @test B̄_diag ≈ B̄_dens
        @test Ā_diag isa BlockDiagonal
        @test blocksizes(Ā_diag, 1) == blocksizes(A, 1)
        @test blocksizes(Ā_diag, 2) == blocksizes(A, 2)
    end
end
