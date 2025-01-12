classdef ResourceFairScheduler < network_elements.lteScheduler
% Scheduler that tries to maximize the user throughput while guaranteeing
% an equal amount of resources for all users
% Stefan Schwarz 
% (c) 2010 by INTHFT
% www.nt.tuwien.ac.at

   properties
       SINR_averager
       CQI_mapping_data
       linprog_options
       alphabets
   end

   methods
       function obj = ResourceFairScheduler(RB_grid_size,Ns_RB,UEs_to_be_scheduled,scheduler_params,CQI_params,averager,mapping_data,alphabets)
           % Fill in basic parameters (handled by the superclass constructor)
            % Fill in basic parameters (handled by the superclass constructor)
           obj = obj@network_elements.lteScheduler(RB_grid_size,Ns_RB,UEs_to_be_scheduled,scheduler_params,CQI_params);
           
           % 0 CQI is not assigned (it means that conditions are out of
           % range to transmit, so no data will be assigned to 0-CQI RBs)
           %obj.assign_zero_CQI = scheduler_params.assign_zero_CQI;
           
           obj.static_scheduler = false;
           obj.SINR_averager = averager;
           % Get a vector of scheduling params (one for each UE)
           % initialized to the values that we want
           obj.UE_static_params = obj.get_initialized_UE_params(scheduler_params,CQI_params);
           obj.CQI_mapping_data = mapping_data;
           obj.linprog_options = optimset('LargeScale','off','Simplex','on','Display','off');
           obj.alphabets = alphabets;
       end

       function UE_scheduling = scheduler_users(obj,subframe_corr,total_no_refsym,SyncUsedElements,UE_output,UE_specific_data,cell_genie,PBCHsyms)
           UE_scheduling = obj.UE_static_params;
           N_UE = size(UE_output,2);
           N_RB = size(UE_output(1).CQI,1)*2;
 
           %% set pmi and ri values
           [UE_scheduling,c,user_ind] = obj.set_pmi_ri(UE_scheduling,N_UE,N_RB,UE_output); 
           c = vec(c);

           %% Resource fair scheduler
           RBs = obj.RF_scheduler(N_UE,N_RB,c);
           
           %% set cqi values
           UE_scheduling = obj.set_cqi(UE_scheduling,user_ind,RBs,N_UE,N_RB,UE_output);
           obj.calculate_allocated_bits(UE_scheduling,subframe_corr,total_no_refsym,SyncUsedElements,PBCHsyms); 
       end
       
       function RBs = RF_scheduler(obj,N_UE,N_RB,c)
           % core scheduling function (same in LL and SL)
           A = kron(eye(N_RB),ones(1,N_UE));
           b = ones(N_RB,1);
           numb = zeros(N_UE,1);
           if ceil(N_RB/N_UE) == floor(N_RB/N_UE) % check wheter N_UE divides N_RB
               numb = N_RB/N_UE*ones(N_UE,1);
           else
               low = floor(N_RB/N_UE);
               high = ceil(N_RB/N_UE);
               x = (N_RB-low*N_UE)/(high-low);
               numb(1:x) = high;
               numb(x+1:end) = low;
               temp = randperm(size(numb,1)); % random permutation of the elements to be fair on average
               numb = numb(temp);
           end
           for i = 1:N_UE
               temp = zeros(1,size(A,2));
               temp(i:N_UE:end) = 1;
               A = [A;temp];
               b = [b;numb(i)];
           end
           RBs = linprog(-c,[],[],A,b,zeros(N_RB*N_UE,1),ones(N_RB*N_UE,1),[],obj.linprog_options);
       end
   end
end 
