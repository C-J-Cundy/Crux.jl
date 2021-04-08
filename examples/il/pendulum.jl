using POMDPs, Crux, Flux, POMDPGym, BSON
import POMDPPolicies:FunctionPolicy
import Distributions:Uniform
using Random
using Distributions

## Pendulum
mdp = PendulumMDP(actions=[-2., -0.5, 0, 0.5, 2.])
as = [actions(mdp)...]
amin = [-1f0]
amax = [1f0]
rand_policy = FunctionPolicy((s) -> Float32.(rand.(Uniform.(amin, amax))))
S = state_space(mdp, σ=[6.3f0, 8f0])

# get expert trajectories
expert_trajectories = BSON.load("examples/il/expert_data/pendulum.bson")[:data]
expert_perf = sum(expert_trajectories[:r]) / length(episodes(expert_trajectories))

# Define the networks we will use
QSA() = ContinuousNetwork(Chain(Dense(3, 64, relu), Dense(64, 64, relu), Dense(64, 1)))
V() = ContinuousNetwork(Chain(Dense(2, 64, relu), Dense(64, 64, relu), Dense(64, 1)))
A() = ContinuousNetwork(Chain(Dense(2, 64, relu, init=Flux.orthogonal), Dense(64, 64, relu, init=Flux.orthogonal), Dense(64, 1, tanh, init=Flux.orthogonal), x -> 2f0 * x), 1)
G() = GaussianPolicy(A(), zeros(Float32, 1))

# This currently doesn't work for some reason
𝒮_gail = GAIL(D=QSA(), gan_loss=GAN_WLossGP(), 𝒟_expert=expert_trajectories, solver=PPO, π=ActorCritic(G(), V()), S=S, N=1000000, ΔN=1024)
solve(𝒮_gail, mdp)

𝒮_bc = BC(π=A(), 𝒟_expert=expert_trajectories, S=S, opt=(epochs=100,), log=(period=10,))
solve(𝒮_bc, mdp)

𝒮_advil = AdVIL(π=ActorCritic(A(),QSA()), 𝒟_expert=expert_trajectories, S=S, a_opt=(epochs=1000, optimizer=ADAM(8f-4), batch_size=1024), c_opt=(optimizer=ADAM(8e-4),), max_steps=100, log=(period=10,))
solve(𝒮_advil, mdp)

𝒮_valueDICE = ValueDICE(;π=ActorCritic(G(), QSA()),
                        𝒟_expert=expert_trajectories, 
                        max_steps=100, 
                        N=Int(1e5), 
                        S=S,
                        α=0.1,
                        buffer_size=Int(1e6), 
                        buffer_init=200,
                        log=(period=100,),
                        c_opt=(batch_size=1024, optimizer=ADAM(1e-5)), 
                        a_opt=(batch_size=1024, optimizer=ADAM(1e-5)))
                        
solve(𝒮_valueDICE, mdp)

using Plots
p = plot_learning([𝒮_gail, 𝒮_bc, 𝒮_advil], title="Pendulum Swingup Imitation Learning Curves", labels=["GAIL", "BC", "AdVIL"], legend=:right)
plot!(p, [1,100000], [expert_perf, expert_perf], color=:black, label="expert")

savefig("pendulum_benchmark.pdf")

