@testset "Common Functions" begin
    network_path = "../test/data/epanet/shamir.inp"
    post_wf = WaterModels.get_post_wf(1.852)
    wm = build_generic_model(network_path, CNLPWaterModel, post_wf)

    @testset "silence" begin
        # This should silence everything except error messages.
        WaterModels.silence()

        im_logger = Memento.getlogger(InfrastructureModels)
        @test Memento.getlevel(im_logger) == "error"
        Memento.warn(im_logger, "Silenced message should not be displayed.")

        wm_logger = Memento.getlogger(WaterModels)
        @test Memento.getlevel(wm_logger) == "error"
        Memento.warn(wm_logger, "Silenced message should not be displayed.")
    end

    @testset "ismultinetwork" begin
        @test ismultinetwork(wm) == false
    end

    @testset "nw_ids" begin
        @test all(nw_ids(wm) .== [0])
    end

    @testset "nws" begin
        @test nws(wm) == wm.ref[:nw]
    end

    @testset "ids" begin
        @test all(ids(wm, 0, :reservoirs) .== [1])
        @test all(ids(wm, :reservoirs) .== [1])
    end

    @testset "ref" begin
        @test ref(wm) == wm.ref[:nw][0]
        @test ref(wm, 0) == wm.ref[:nw][0]
        @test ref(wm, :reservoirs) == wm.ref[:nw][0][:reservoirs]
        @test ref(wm, 0, :reservoirs) == wm.ref[:nw][0][:reservoirs]
        @test ref(wm, :reservoirs, 1) == wm.ref[:nw][0][:reservoirs][1]
        @test ref(wm, 0, :reservoirs, 1) == wm.ref[:nw][0][:reservoirs][1]
        @test ref(wm, 0, :reservoirs, 1, "head") == 210.0
    end

    @testset "var" begin
        @test var(wm, 0) == wm.var[:nw][0]
        @test var(wm, 0, :qn) == wm.var[:nw][0][:qn]
        @test var(wm, 0, :qn, 1) == wm.var[:nw][0][:qn][1]
    end

    @testset "con" begin
        @test con(wm, 0) == wm.con[:nw][0]
        @test con(wm, 0, :flow_conservation) == wm.con[:nw][0][:flow_conservation]
        @test con(wm, 0, :flow_conservation, 2) == wm.con[:nw][0][:flow_conservation][2]
    end
end
