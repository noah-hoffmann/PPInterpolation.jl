using LinearAlgebra

export CubicPP, makeLinearCubicPP, makeCubicPP, C2, C2Hyman89, C2HymanNonNegative, C2MP, Bessel, HuynRational, VanAlbada, VanLeer, FritchButland
export evaluateDerivative, evaluateSecondDerivative

abstract type DerivativeKind end
struct C2 <: DerivativeKind end
struct C2Hyman89 <: DerivativeKind end
struct C2HymanNonNegative <: DerivativeKind end
struct C2MP <: DerivativeKind end
struct C2MP2 <: DerivativeKind end

struct CubicPP{T<:Real,TX}
    a::AbstractArray{T}
    b::AbstractArray{T}
    c::AbstractArray{T}
    d::AbstractArray{T}
    x::AbstractArray{TX}
    CubicPP(T, TX, n::Int) = new{T,TX}(zeros(T, n), zeros(T, n), zeros(T, n - 1), zeros(T, n - 1), zeros(TX, n))
    CubicPP(a::AbstractArray{T}, b::AbstractArray{T}, c::AbstractArray{T}, d::AbstractArray{T}, x::AbstractArray{TX}) where {T<:Real,TX} =
        new{T,TX}(a, b, c, d, x)
end
# abstract type PPBoundary <: Real end
# struct FirstDerivativeBoundary <: PPBoundary end
# struct SecondDerivativeBoundary <: PPBoundary end
@enum PPBoundary NOT_A_KNOT = 0 FIRST_DERIVATIVE = 1 SECOND_DERIVATIVE = 2 FIRST_DIFFERENCE = 3

Base.length(p::CubicPP) = Base.length(p.x)
Base.broadcastable(p::CubicPP) = Ref(p)


function makeLinearCubicPP(x::AbstractArray{TX}, y::AbstractArray{T}) where {T,TX}
    pp = CubicPP(T, TX, length(y))
    computeLinearCubicPP(pp, x, y)
    return pp
end

function computeLinearCubicPP(pp::CubicPP{T,TX}, x::AbstractArray{TX}, y::AbstractArray{T}) where {T,TX}
    n = length(x)
    if n <= 1
        pp.a[1:end] = y
        pp.b[1:end] = zeros(n)
        pp.c[1:end] = zeros(n - 1)
        pp.d[1:end] = zeros(n - 1)
        pp.x[1:end] = x
    elseif n == 2
        t = y[2] - y[1]
        b = zeros(n)
        if abs(x[2] - x[1]) > eps()
            b[1] = t / (x[2] - x[1])
        end
        b[2] = b[1]
        pp.a[1:end] = y
        pp.b[1:end] = b
        pp.c[1:end] = zeros(n - 1)
        pp.d[1:end] = zeros(n - 1)
        pp.x[1:end] = x
    else
        # on xi, xi+1, f(x)= yi (xi+1-x) + yi (x-xi) = A + B (x-xi) => B = (yi-yi+1)/(xi-xi+1)
        b = zeros(n)
        for i = 1:n-1
            b[i] = (y[i+1] - y[i]) / (x[i+1] - x[i])
        end
        pp.a[1:end] = y
        pp.b[1:end] = b
        pp.c[1:end] = zeros(n - 1)
        pp.d[1:end] = zeros(n - 1)
        pp.x[1:end] = x
    end
end

function makeCubicPP(
    x::AbstractArray{TX},
    y::AbstractArray{T},
    leftBoundary::PPBoundary,
    leftValue::T,
    rightBoundary::PPBoundary,
    rightValue::T,
    kind::DerivativeKind,
) where {T,TX}
    pp = CubicPP(T, TX, length(y))
    computeCubicPP(pp, x, y, leftBoundary, leftValue, rightBoundary, rightValue, kind)
    return pp
end

function computeCubicPP(
    pp::CubicPP{T,TX},
    x::AbstractArray{TX},
    y::AbstractArray{T},
    leftBoundary::PPBoundary,
    leftValue::T,
    rightBoundary::PPBoundary,
    rightValue::T,
    kind::Union{C2,C2Hyman89,C2HymanNonNegative,C2MP, C2MP2},
) where {T,TX}
    n = length(y)
    if n <= 2
        return makeLinearCubicPP(x, y)
    end

    dx = x[2:end] - x[1:end-1]
    S = (y[2:end] - y[1:end-1]) ./ dx
    middle = zeros(n)
    alpha = zeros(n)
    lower = zeros(n - 1)
    upper = zeros(n - 1)
    for i = 2:n-1
        lower[i-1] = dx[i]
        upper[i] = dx[i-1]
        middle[i] = 2 * (dx[i] + dx[i-1])
        alpha[i] = 3.0 * (dx[i] * S[i-1] + dx[i-1] * S[i])
    end
    #middle[2:n-1] = 3 * (dx[2:n-1] + dx[1:n-2])
    #alpha[2:n-1] = 3 * (dx[2:n-1] .* S[1:n-2] + dx[1:n-2] .* S[2:n-1])
    if leftBoundary == NOT_A_KNOT
        middle[1] = dx[2] * (dx[2] + dx[1])
        upper[1] = (dx[2] + dx[1]) * (dx[2] + dx[1])
        alpha[1] = S[1] * dx[2] * (2.0 * dx[2] + 3.0 * dx[1]) + S[2] * dx[1]^2
    elseif leftBoundary == FIRST_DERIVATIVE
        middle[1] = 1.0
        upper[1] = 0.0
        alpha[1] = leftValue
    elseif leftBoundary == FIRST_DIFFERENCE
        middle[1] = 1.0
        upper[1] = 0.0
        alpha[1] = S[1]
    elseif leftBoundary == SECOND_DERIVATIVE
        middle[1] = 2.0
        upper[1] = 1.0
        alpha[1] = 3 * S[1] - leftValue * dx[1] / 2
    end
    if rightBoundary == NOT_A_KNOT
        lower[n-1] = -(dx[n-1] + dx[n-2]) * (dx[n-1] + dx[n-2])
        middle[n] = -dx[n-2] * (dx[n-2] + dx[n-1])
        alpha[n] = -S[n-2] * dx[n-1]^2 - S[n-1] * dx[n-2] * (3.0 * dx[n-1] + 2.0 * dx[n-2])
    elseif rightBoundary == FIRST_DERIVATIVE
        middle[n] = 1.0
        lower[n-1] = 0.0
        alpha[n] = rightValue
    elseif rightBoundary == FIRST_DIFFERENCE
        middle[n] = 1.0
        lower[n-1] = 0.0
        alpha[n] = S[n-1]
    elseif rightBoundary == SECOND_DERIVATIVE
        middle[n] = 2.0
        lower[n-1] = 1.0
        alpha[n] = 3 * S[n-1] - rightValue * dx[n-1] / 2
    end
    tri = LinearAlgebra.Tridiagonal(lower, middle, upper)
    fPrime = tri \ alpha
    filterSlope(kind, y, fPrime, dx, S)
    c = (3 * S - fPrime[2:end] - 2 * fPrime[1:end-1]) ./ dx
    d = (fPrime[2:end] + fPrime[1:end-1] - 2 * S) ./ (dx .^ 2)
    pp.a[1:end] = y
    pp.b[1:end] = fPrime
    pp.c[1:end] = c
    pp.d[1:end] = d
    pp.x[1:end] = x
end

function filterSlope(kind::C2, y::AbstractArray{T}, b::AbstractArray{T}, dx::AbstractArray{TX}, S::AbstractArray{T}) where {T,TX}
    #do nothing
end


function filterSlope(kind::C2MP, y::AbstractArray{T}, b::AbstractArray{T}, dx::AbstractArray{TX}, S::AbstractArray{T}) where {T,TX}
    n = length(y)
    if S[1] > 0
        b[1] = min(max(0, b[1]), 3 * S[1])
    else
        b[1] = max(min(0, b[1]), 3 * S[1])
    end
    if S[n-1] > 0
        b[n] = min(max(0, b[n]), 3 * S[n-1])
    else
        b[n] = max(min(0, b[n]), 3 * S[n-1])
    end

    for i = 2:n-1
        Sim = S[i-1]
        Sip = S[i]
        if Sim * Sip <= 0
            b[i] = 0
        elseif Sim > 0 && Sip > 0
            b[i] = min(max(0, b[i]), 3 * min(Sim, Sip))
        else
            b[i] = max(min(0, b[i]), 3 * max(Sim, Sip))
        end
    end
end

minmod(s::T,t::T) where{T} = s*t <= 0 ? zero(T) : sign(s)*min(abs(s),abs(t)) 


function filterSlope(kind::C2MP2, y::AbstractArray{T}, b::AbstractArray{T}, dx::AbstractArray{TX}, S::AbstractArray{T}) where {T,TX}
    #r = s/t and G = t*g(r)
    n = length(y)
    b[1] = minmod(b[1], 3*S[1])
    b[n] = minmod(b[n], 3 * S[n-1])

    for i = 2:n-1
        Sim = S[i-1]
        Sip = S[i]
        lowerBound = minmod(Sim,Sip)
        upperBound = (sign(Sim) + sign(Sip))/2 * min(max(abs(Sim),abs(Sip)),3*min(abs(Sim),abs(Sip)))
        b[i] = min(max(lowerBound,b[i]),upperBound)      
    end
end


function filterSlope(kind::C2HymanNonNegative, y::AbstractArray{T}, b::AbstractArray{T}, dx::AbstractArray{TX}, S::AbstractArray{T}) where {T,TX}
    n = length(y)
    tau0 = sign(y[1])
    #Warning the paper (3.3) is wrong as it does not obey (3.1)
    b[1] = tau0 * max(-3 * tau0 * y[1] / dx[1], tau0 * b[1])
    for i = 2:n-1
        taui = sign(y[i])
        b[i] = taui * min(3 * taui * y[i] / dx[i-1], max(-3 * taui * y[i] / dx[i], taui * b[i]))
    end
    taun = sign(y[n])
    b[n] = taun * min(3 * taun * y[n] / dx[n-1], taun * b[n])
end

function filterSlope(kind::C2Hyman89, y::AbstractArray{T}, b::AbstractArray{T}, dx::AbstractArray{TX}, S::AbstractArray{T}) where {T,TX}
    n = length(y)
    tmp = b

    local correction, pm, pu, pd, M
    if (tmp[1] * S[1]) > 0
        correction = sign(tmp[1]) * min(abs(tmp[1]), abs(3 * S[1]))
    else
        correction = zero(T)
    end
    if correction != tmp[1]
        tmp[1] = correction
    end
    for i = 2:n-1
        pm = ((S[i-1] * dx[i]) + (S[i] * dx[i-1])) / (dx[i-1] + dx[i])
        M = 3 * min(min(abs(S[i]), abs(S[i-1])), abs(pm))
        if i > 2
            if ((S[i-1] - S[i-2]) * (S[i] - S[i-1])) > 0
                pd = ((S[i-1] * ((2 * dx[i-1]) + dx[i-2])) - (S[i-2] * dx[i-1])) / (dx[i-2] + dx[i-1])
                if (pm * pd) > 0 && (pm * (S[i-1] - S[i-2])) > 0
                    M = max(M, 3 * min(abs(pm), abs(pd)) / 2)
                end
            end
        end
        if i < (n - 1)
            if ((S[i] - S[i-1]) * (S[i+1] - S[i])) > 0
                pu = ((S[i] * ((2 * dx[i]) + dx[i+1])) - (S[i+1] * dx[i])) / (dx[i] + dx[i+1])
                if ((pm * pu) > 0) && ((-pm * (S[i] - S[i-1])) > 0)
                    M = max(M, 3 * min(abs(pm), abs(pu)) / 2)
                end
            end
        end
        if (tmp[i] * pm) > 0
            correction = sign(tmp[i]) * min(abs(tmp[i]), M)
        else
            correction = zero(T)
        end
        if correction != tmp[i]
            tmp[i] = correction
        end
    end
    if (tmp[n] * S[n-1]) > 0
        correction = sign(tmp[n]) * min(abs(tmp[n]), abs(3 * S[n-1]))
    else
        correction = zero(T)
    end
    if correction != tmp[n]
        tmp[n] = correction
    end
end


function estimateDerivativeParabolic(x::AbstractArray{TX}, y::AbstractArray{T}) where {T,TX}
    n = length(x)
    b = zeros(n)
    dx = x[2:end] - x[1:end-1]
    S = (y[2:end] - y[1:end-1]) ./ dx
    for i = 2:n-1
        b[i] = (dx[i-1] * S[i] + dx[i] * S[i-1]) / (dx[i-1] + dx[i])
    end
    return b
end

abstract type LimiterDerivative <: DerivativeKind end
struct Hermite <: DerivativeKind end
struct Bessel <: LimiterDerivative end
struct HuynRational <: LimiterDerivative end
struct VanLeer <: LimiterDerivative end
struct VanAlbada <: LimiterDerivative end
struct FritschButland <: LimiterDerivative end #Fritsch Butland 1980
struct Brodlie <: LimiterDerivative end #Fritch Butland 1984


function limit(::HuynRational, s::T, t::T) where {T}
    st = s * t
    if st <= 0
        return zero(T)
    end
    return st * 3 * (s + t) / (s^2 + 4 * st + t^2)
end

function limit(::VanAlbada, s::T, t::T) where {T}
    return s * t * (s + t) / (s^2 + t^2)
end

function limit(::VanLeer, s::T, t::T) where {T}
    st = s * t
    if st <= 0
        return zero(T)
    end
    return 2 * st / (s + t) #warning, the product s*t can be zero even when s or t are not 0, this rewrite helps saving accuracy
end

function limit(::FritschButland, s::T, t::T) where {T}
    st = s * t
    if st <= 0
        return zero(T)
    end
    if abs(s) <= abs(t)
        return 3 * st / (2 * s + t)
    end
    return 3 * st / (s + 2 * t)   # (1+dxp / (dxp+dx)) * t + (2 - dxp / (dxp+dx)) * s
end

function fillDerivativeEstimate(limiter::LimiterDerivative, dx::AbstractArray{TX}, S::AbstractArray{T}, b::AbstractArray{T}) where {T,TX}
    n = length(S)
    for i = 2:n
        s, t = S[i-1], S[i]
        b[i] = limit(limiter, s, t)
    end
end

function fillDerivativeEstimate(limiter::Bessel, dx::AbstractArray{TX}, S::AbstractArray{T}, b::AbstractArray{T}) where {T,TX}
    n = length(S)
    for i = 2:n
        b[i] = (dx[i-1] * S[i] + dx[i] * S[i-1]) / (dx[i-1] + dx[i])
    end
end


function fillDerivativeEstimate(limiter::Brodlie, dx::AbstractArray{TX}, S::AbstractArray{T}, b::AbstractArray{T}) where {T,TX}
    n = length(S)
    for i = 2:n
        s, t = S[i-1], S[i]
        α = (dx[i-1] + 2 * dx[i]/(3*(dx[i-1]+dx[i])))
        b[i] = (s*t) / (α * t + (1-α)*s)
    end
end

function computeCubicPP(
    pp::CubicPP{T,TX},
    x::AbstractArray{TX},
    y::AbstractArray{T},
    leftBoundary::PPBoundary,
    leftValue::T,
    rightBoundary::PPBoundary,
    rightValue::T,
    limiter::LimiterDerivative,
) where {T,TX}
    n = length(y)
    if n <= 2
        return makeLinearCubicPP(x, y)
    end

    dx = x[2:end] - x[1:end-1]
    S = (y[2:end] - y[1:end-1]) ./ dx
    b = pp.b
    fillDerivativeEstimate(limiter, dx, S, b)
    if leftBoundary == NOT_A_KNOT
        b[1] = S[2] * dx[1] / (dx[2] * (dx[2] + dx[1])) - S[1] * ((dx[2] / dx[1] + 2) / (dx[2] + dx[1]))
    elseif leftBoundary == FIRST_DIFFERENCE
        b[1] = S[1]
    elseif leftBoundary == FIRST_DERIVATIVE
        b[1] = leftValue
    elseif leftBoundary == SECOND_DERIVATIVE
        #c[1] = leftValue * 0.5
        b[1] = (-leftValue / 2 * dx[1] - b[2] + 3 * S[1]) / 2
    end
    if rightBoundary == NOT_A_KNOT
        b[n] =
            S[n-2] * dx[n-1] / (dx[n-2] * (dx[n-2] + dx[n-1])) -
            S[n-1] * ((dx[n-2] / dx[n-1] + 2) / (dx[n-2] + dx[n-1]))
    elseif rightBoundary == FIRST_DERIVATIVE
        b[n] = rightValue
    elseif rightBoundary == FIRST_DIFFERENCE
        b[n] = S[n-1]
    elseif rightBoundary == SECOND_DERIVATIVE
        b[n] = (rightValue * dx[n-1] + 6 * S[n-1] - 2 * b[n-1]) / 4
    end
    c = (3 * S - b[2:end] - 2 * b[1:end-1]) ./ dx
    d = (b[2:end] + b[1:end-1] - 2 * S) ./ (dx .^ 2)

    pp.a[1:end] = y
    pp.c[1:end] = c
    pp.d[1:end] = d
    pp.x[1:end] = x
end


function evaluate(self::CubicPP{T,TX}, z::TZ) where {T,TX,TZ}
    if z <= self.x[1]
        return self.b[1] * (z - self.x[1]) + self.a[1]
    elseif z >= self.x[end]
        return self.b[end] * (z - self.x[end]) + self.a[end]
    end
    i = searchsortedfirst(self.x, z)  # x[i-1]<z<=x[i]
    if z != self.x[i] && i > 1
        i -= 1
    end
    h = z - self.x[i]
    return self.a[i] + h * (self.b[i] + h * (self.c[i] + h * (self.d[i])))
end

function evaluateDerivative(self::CubicPP{T,TX}, z::TZ) where {T,TX,TZ}
    if z <= self.x[1]
        return self.b[1]
    elseif z >= self.x[end]
        rightSlope = self.b[end]
        return rightSlope
    end
    i = searchsortedfirst(self.x, z)  # x[i-1]<z<=x[i]
    if z != self.x[i] && i > 1
        i -= 1
    end
    h = z - self.x[i]
    return self.b[i] + h * (2 * self.c[i] + h * (3 * self.d[i]))
end
function evaluateSecondDerivative(self::CubicPP{T,TX}, z::TZ) where {T,TX,TZ}
    if z <= self.x[1]
        return self.b[1]
    elseif z >= self.x[end]
        rightSlope = self.b[end]
        return rightSlope
    end
    i = searchsortedfirst(self.x, z)  # x[i-1]<z<=x[i]
    if z != self.x[i] && i > 1
        i -= 1
    end
    h = z - self.x[i]
    return 2 * self.c[i] + h * (3 * 2 * self.d[i])
end

(spl::CubicPP{T,TX})(x::TZ) where {T,TX,TZ} = evaluate(spl, x)
