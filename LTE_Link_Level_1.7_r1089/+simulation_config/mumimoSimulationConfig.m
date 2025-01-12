classdef mumimoSimulationConfig < simulation_config.simulatorConfig
    % Simulation parameters for a MUMIMO simulation
    
    methods (Static)
        function LTE_params = apply_parameters(LTE_params)
            LTE_params.nUE = 2;     % number of user equipments to simulate
            LTE_params.nBS = 1;     % number of base stations to simulate (hard-coded to 1)
            LTE_params.Bandwidth = 1.4e6;            % in Hz, allowed values: 1.4 MHz, 3 MHz, 5 MHz, 10 MHz, 15 MHz, 20MHz => number of resource blocks 6, 15, 25, 50, 75, 100
            LTE_params.introduce_timing_offset =  false;
            LTE_params.introduce_frequency_offset =  false;
            %% Define some User parameters (identical settings).
            LTE_params.UE_config.channel_estimation_method = 'PERFECT';      %'PERFECT','LS','MMSE'
            LTE_params.UE_config.mode = 3;                     % DEFINED IN STANDARD 3GPP TS 36.213-820 Section 7.1, page 12
            % 1: Single Antenna, 2: Transmit Diversity, 3: Open Loop Spatial Multiplexing
            % 4: Closed Loop SM, 5:
            % Multiuser MIMO
            LTE_params.UE_config.nRX = 2;                      % number of receive antennas at UE
            LTE_params.UE_config.receiver = 'ZF'; % 'SSD','ZF'
            fd = 0; % Doppler frequency
            LTE_params.UE_config.user_speed = fd/LTE_params.carrier_freq*LTE_params.speed_of_light;  % [km/h]
            LTE_params.UE_config.timing_offset = 23;   % timing offset in number of time samples
            LTE_params.UE_config.timing_sync_method = 'perfect';% 'perfect','none', 'autocorrelation'
            LTE_params.UE_config.carrier_freq_offset = pi;   % carrier frequency offset normalized to subcarrier spacing
            LTE_params.UE_config.freq_sync_method = 'perfect';
            LTE_params.UE_config.rfo_correct_method = 'subframe'; % 'none','subframe'
            %% Define BS parameters (identical settings).
            LTE_params.BS_config.nTx = 2;
            %% Define ChanMod parameters - now it is only possible to have same channel parameters for BS and UE
            LTE_params.ChanMod_config.filtering = 'BlockFading';  %'BlockFading','FastFading'
            LTE_params.ChanMod_config.type = 'TU'; % 'PedA', 'PedB', 'PedBcorr', 'AWGN', 'flat Rayleigh','VehA','VehB','TU','RA','HT','winner_II'
            %% Scheduler settings
            LTE_params.scheduler.type = 'round robin';
            %        LTE_params.scheduler.type = 'constrained scheduler';
            % Available options are:
            %   - 'round robin': Will serve equally all of the available users
            %   - 'best cqi'   : Will serve only users that maximize the CQI for specific RB
            %   - 'fixed'
            
            LTE_params.scheduler.assignment = 'static';
            %         LTE_params.scheduler.assignment = 'dynamic';
            % Available options are:
            %   - For 'round robin': 'static' of 'dynamic': whether the scheduler will statically
            %     assign or dynamically assign CQIs and other params. Currently only 'static' is implemented
            %   - For 'best cqi': 'dynamic': the scheduler will dynamically assign CQIs and other params.
            %   - For 'fixed': a vector stating how many RBs will each user get.
            
            % Parameters for the static scheduler
            LTE_params.scheduler.cqi  = 'set';
            LTE_params.scheduler.PMI  = 2;              % corresponds CI for closed loop SM
        end
    end
end

