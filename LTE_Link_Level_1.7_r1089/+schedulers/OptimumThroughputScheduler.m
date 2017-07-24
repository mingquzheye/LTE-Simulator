classdef OptimumThroughputScheduler < network_elements.lteScheduler
% Scheduler that tries to come close to the optimum (maximum) throughput
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
       function obj = OptimumThroughputScheduler(RB_grid_size,Ns_RB,UEs_to_be_scheduled,scheduler_params,CQI_params,averager,mapping_data,alphabets)
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
           N_RB = size(UE_output(1).CQI,1)*2;
           N_UE = size(UE_output,2);
           for uu = 1:N_UE
               UE_scheduling(uu).CQI_params = [];
               if ~isempty(UE_output(uu).PMI)   % check wheter PMI is fed back
                   if ~isempty(UE_output(uu).RI)    % check wheter RI is fed back
                        UE_scheduling(uu).nLayers = UE_output(uu).RI;
                        UE_scheduling(uu).nCodewords = min(2,UE_output(uu).RI);
                   end
               UE_scheduling(uu).PMI = UE_output(uu).PMI;
               end
           end
           
           % this search over all possibilities needs toooooo much time!
%            rate_tot = zeros(3^N_RB,1);
%            for rb_i = 1:3^N_RB-1
%                rb_assign = dec2base(rb_i,3,N_RB);
%                rate = 0;
%                for ue_i = 1:N_UE
%                    UE_assign = reshape((rb_assign == num2str(ue_i)),6,2);
%                    CQI_temp = (UE_output(ue_i).CQI(UE_assign));
%                    if ~isempty(CQI_temp)
%                        SINRs = zeros(size(obj.CQI_mapping_data));
%                        SINR_temp = obj.SINR_averager.average(10.^((obj.CQI_mapping_data.table(mod(CQI_temp,20)+1)+obj.CQI_mapping_data.table(mod(CQI_temp,20)+2))/20),0:15,obj.alphabets);
%                        SINRs = SINR_temp(:);
%                        temp = zeros(size(SINRs));
%                        temp(obj.CQI_mapping_data.table(1:16) <= SINRs) = 1;
%                        temp_CQI = find(temp,1,'last')-1;
%                        if temp_CQI
%                             rate = rate + obj.CQI_params(temp_CQI).efficiency;
%                        end
%                    end
%                end
%                if ~mod(rb_i,5000)
%                    disp(rb_i);
%                end
%                rate_tot(rb_i) = rate;
%            end   
%            max_rate = max(rate_tot);
%            indis = find(rate_tot == max_rate);


           % first stage: determine RB sets assigned to each UE
           % according to the CQI (best CQI)
           for u_=1:N_UE % calculate sum efficiencies for both codewords on every RB
               UE_scheduling(u_).UE_mapping = false(obj.RB_grid_size,2);
               eff_temp(:,u_) = sum(reshape([obj.CQI_params(UE_output(u_).CQI(:,:,1:UE_scheduling(u_).nCodewords)).efficiency],obj.RB_grid_size*2,UE_scheduling(u_).nCodewords),2);
           end % based on this value the decision is carried out which UE gets an RB
%            [~,Indis] = max(eff_temp,[],2);

           Indis = zeros(size(eff_temp,1),1);
           for r_ = 1:size(eff_temp,1)  % include randomization into the decision to make the scheduler fair if some UEs have equal CQIs
              maxi = max(eff_temp(r_,:));
              indis = find(eff_temp(r_,:) == maxi);
              ind = randi(length(indis),1);
              Indis(r_) = indis(ind);
           end
           for u_=1:N_UE
               UE_scheduling(u_).UE_mapping(Indis == u_) = true; 
           end

           rate_tot = zeros(2,1);
           max_indi_choice = zeros(2,2);
           for i1 = 1:2 % serve first UE1 and then UE2 or the other way around
               UE_map(1,i1).mapping = UE_scheduling(1).UE_mapping;
               UE_map(2,i1).mapping = UE_scheduling(2).UE_mapping;
               if i1 == 1
                   UE_counter = [1,2];
               else
                   UE_counter = [2,1];
               end
               max_rate = zeros(2,1);
               for uu = UE_counter
                   max_CQI = max(UE_output(uu).CQI(UE_map(uu,i1).mapping));
                   max_CQI_ind = find(UE_output(uu).CQI(UE_map(uu,i1).mapping) == max_CQI);
                   max_CQI_numb = length(max_CQI_ind);
                   RB_numb = sum(sum(UE_map(uu,i1).mapping));
                   if RB_numb ~= 0
                       RB_ind = find(UE_map(uu,i1).mapping & UE_output(uu).CQI ~= max_CQI);
                       temp_mapping = false(size(UE_map(uu,i1).mapping));
                       temp_mapping(UE_output(uu).CQI == max_CQI & UE_map(uu,i1).mapping) = true;
                       rate = zeros(2^(RB_numb-max_CQI_numb),1);
                       for rb_i = 0:2^(RB_numb-max_CQI_numb)-1
                           if (RB_numb-max_CQI_numb)
                                RBs = false(RB_numb-max_CQI_numb,1);
                                RBs(dec2bin(rb_i,RB_numb-max_CQI_numb) == '1') = true;
                                temp_mapping(RB_ind) = RBs; 
                           end
                           CQI_temp = UE_output(uu).CQI(temp_mapping);
                           SINRs = zeros(size(obj.CQI_mapping_data));
                           SINR_temp = obj.SINR_averager.average(10.^((obj.CQI_mapping_data.table(mod(CQI_temp,20)+1)+0.95*obj.CQI_mapping_data.table(mod(CQI_temp,20)+2))/20),0:15,obj.alphabets);
                           SINRs = SINR_temp(:);
                           temp = zeros(size(SINRs));
                           temp(obj.CQI_mapping_data.table(1:16) <= SINRs) = 1;
                           temp_CQI = find(temp,1,'last')-1;
                           if temp_CQI
                                if(subframe_corr == 1 || subframe_corr == 6)
                                    %lenghts of primary and secondary synchronization channels (symbols)
                                    sync_symbols = sum(sum(SyncUsedElements(UE_scheduling(u_).UE_mapping)));               
                                else
                                    sync_symbols = 0;
                                end
                                CHsyms = sum(sum(PBCHsyms(UE_scheduling(u_).UE_mapping)));
%                                 rate(rb_i+1) = obj.CQI_params(temp_CQI).efficiency*sum(sum(temp_mapping));
                                rate(rb_i+1) = 8*round(1/8*obj.CQI_params(temp_CQI).efficiency*(sum(sum(temp_mapping))*(obj.Ns_RB - total_no_refsym) - sync_symbols - CHsyms))-24;
%                                 rate(rb_i+1)
                           end
                       end
                       max_rate(uu) = max(rate);
                       max_indi = find(rate == max_rate(uu));
                   else 
                       max_rate(uu) = 0;
                       max_indi = 0;
                   end
                   if length(max_indi) > 1
                       max_indi = randperm(length(max_indi));
                       max_indi_choice(uu,i1) = max_indi(1);
                   else
                       max_indi_choice(uu,i1) = max_indi;
                   end
                   if RB_numb ~= 0
                       temp_mapping = false(size(UE_map(uu,i1).mapping));
                       temp_mapping(UE_output(uu).CQI == max_CQI & UE_map(uu,i1).mapping) = true;
                       if (RB_numb-max_CQI_numb)
                            RBs = false(RB_numb-max_CQI_numb,1);
                            RBs(dec2bin(max_indi_choice(uu,i1)-1,RB_numb-max_CQI_numb) == '1') = true;
                            temp_mapping(RB_ind) = RBs; 
                       end
                       UE_map(uu,i1).mapping = temp_mapping;
                       if max_indi_choice(uu,i1) < length(rate) && uu == UE_counter(1) 
    %                        UE_scheduling(uu).UE_mapping=temp_mapping;
                           UE_map(UE_counter(2),i1).mapping = UE_map(UE_counter(2),i1).mapping | ~temp_mapping;
                       end
                   end
                   rate_tot(i1) = rate_tot(i1)+max_rate(uu);
               end
           end 
           maximum = max(rate_tot);
           maximum_ind = find(rate_tot == maximum);
           if length(maximum_ind) > 1
               max_indi = randperm(length(maximum_ind));
               maximum_ind_choice = max_indi_choice(:,max_indi(1));
           else
               max_indi = maximum_ind;
               maximum_ind_choice = max_indi_choice(:,maximum_ind);
           end
           for uu = 1:2
               UE_scheduling(uu).UE_mapping = UE_map(uu,max_indi(1)).mapping;
               if sum(sum(UE_scheduling(uu).UE_mapping))
                   CQI_temp = UE_output(uu).CQI(UE_scheduling(uu).UE_mapping);
                   SINRs = zeros(size(obj.CQI_mapping_data));
                   SINR_temp = obj.SINR_averager.average(10.^((obj.CQI_mapping_data.table(mod(CQI_temp,20)+1)+0.95*obj.CQI_mapping_data.table(mod(CQI_temp,20)+2))/20),0:15,obj.alphabets);
                   SINRs = SINR_temp(:);
                   temp = zeros(size(SINRs));
                   temp(obj.CQI_mapping_data.table(1:16) <= SINRs) = 1;
                   temp_CQI = find(temp,1,'last')-1;
                   if temp_CQI
                        UE_scheduling(uu).cqi(1) = temp_CQI;
                   else
                        UE_scheduling(uu).cqi(1) = 1; % this is the rate 0 CQI
                   end
               else
                   UE_scheduling(uu).cqi(1) = 1;
               end
           end
           for uu = 1:N_UE
               UE_scheduling(uu).assigned_RBs = squeeze(sum(sum(UE_scheduling(uu).UE_mapping,1),2));
               UE_scheduling(uu).CQI_params = [UE_scheduling(uu).CQI_params,LTE_common_get_CQI_params(UE_scheduling(uu).cqi,obj.CQI_params)];
           end
           UE_scheduling.UE_mapping
           UE_scheduling.cqi

           obj.calculate_allocated_bits(UE_scheduling,subframe_corr,total_no_refsym,SyncUsedElements,PBCHsyms);
          
       end
   end
end 
