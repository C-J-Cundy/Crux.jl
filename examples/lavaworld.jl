using POMDPs, Crux, Flux, POMDPGym

## LavaWorld
mdp = LavaWorldMDP()
as = [actions(mdp)...]
S = state_space(mdp)

# Define the networks we will use
Q() = Chain(x -> reshape(x, 105, :), Dense(105, 64, relu), Dense(64, 64, relu), Dense(64, length(as)))
A() = Chain(x -> reshape(x, 105, :), Dense(105, 64, relu), Dense(64, 64, relu), Dense(64, length(as)), softmax)
V() = Chain(x -> reshape(x, 105, :), Dense(105, 32, relu), Dense(32, 32, relu), Dense(32, 1))

# Solve with REINFORCE
𝒮_reinforce = PGSolver(π = CategoricalPolicy(A(), as),
                S = S, N=20000, ΔN = 500, loss = reinforce())
π_reinforce = solve(𝒮_reinforce, mdp)

# Solve with A2C
𝒮_a2c = PGSolver(π = ActorCritic(CategoricalPolicy(A(), as), V()), 
                S = S, N=20000, ΔN = 500, loss = a2c())
π_a2c = solve(𝒮_a2c, mdp)

# Solve with PPO
𝒮_ppo = PGSolver(π = ActorCritic(CategoricalPolicy(A(), as), V()), 
                S = S, N=20000, ΔN = 500, loss = ppo())
π_ppo = solve(𝒮_ppo, mdp)

# Solve with DQN
𝒮_dqn = DQNSolver(π = DQNPolicy(Q(), as), S = S, N = 20000)
π_dqn = solve(𝒮_dqn, mdp)

# Plot the learning curve
p = plot_learning([𝒮_reinforce, 𝒮_a2c, 𝒮_ppo, 𝒮_dqn], title = "Lavaworld Training Curves", labels = ["REINFORCE", "A2C", "PPO", "DQN"])

# Produce a gif with the final policy
gif(mdp, π_ppo, "lavaworld_policy.gif")

