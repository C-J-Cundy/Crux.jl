using Crux
using Test

##  MultitaskDecay Schedule
m = MultitaskDecaySchedule(10, [1,2,3])
l = Crux.LinearDecaySchedule(1.0, 0.1, 10)

for i=1:10
    @test m(i) == l(i)
end

for i=11:20
    @test m(i) == l(i-10)
end

for i=21:30
    @test m(i) == l(i-20)
end

m = MultitaskDecaySchedule(10, [1,2,1])

for i=1:10
    @test m(i) == l(i)
end

for i=11:20
    @test m(i) == l(i-10)
end

for i=21:30
    @test m(i) == l(i-10)
end

@test m(31) == 0.1
@test m(0) == 1

## gradient penalty
m = Dense(2,1, init=ones, bias=false)
x = ones(Float32, 2, 100)
@test gradient_penalty(m, x) ≈ (sqrt(2) - 1)^2

