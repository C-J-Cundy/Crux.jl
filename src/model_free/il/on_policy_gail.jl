function GAIL_D_loss(gan_loss)
    (D, 𝒫, 𝒟_ex, 𝒟_π; info = Dict()) ->begin
        Lᴰ(gan_loss, D, 𝒟_ex[:a], 𝒟_π[:a], yD = (𝒟_ex[:s],), yG = (𝒟_π[:s],))
    end
end

function OnPolicyGAIL(;π, S, A=action_space(π), 𝒟_demo, normalize_demo::Bool=true, D::ContinuousNetwork, solver=PPO, gan_loss::GANLoss=GAN_BCELoss(), d_opt::NamedTuple=(;), log::NamedTuple=(;),  kwargs...)
    d_opt = TrainingParams(;loss = GAIL_D_loss(gan_loss), name="discriminator_", d_opt...)
    normalize_demo && (𝒟_demo = normalize!(deepcopy(𝒟_demo), S, A))
    𝒟_demo = 𝒟_demo |> device(π)
    
    function GAIL_callback(𝒟; info=Dict())
        batch_train!(D, d_opt, (;), 𝒟_demo, 𝒟, info=info)
        
        discriminator_signal = haskey(𝒟, :advantage) ? :advantage : :return
        D_out = value(D, 𝒟[:a], 𝒟[:s])
        r = Base.log.(sigmoid.(D_out) .+ 1f-5) .- Base.log.(1f0 .- sigmoid.(D_out) .+ 1f-5)
        𝒟[discriminator_signal] .= r # This is swapped because a->x and s->y and the convention for GANs is D(x,y)
    end
    𝒮 = solver(;π=π, S=S, A=A, post_batch_callback=GAIL_callback, log=(dir="log/onpolicygail", period=500, log...), kwargs...)
    𝒮.c_opt = nothing # disable the critic 
    𝒮
end