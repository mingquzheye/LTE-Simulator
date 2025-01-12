classdef VarFairScheduler < network_elements.lteScheduler
% Variable fair scheduler based on the proportional fair scheduler presented in 
% "Reduced-Complexity Proportional Fair Scheduling for OFDMA Systems"
% Z. Sun, C. Yin, G. Yue, IEEE 2006 International Conference on Communications, Circuits and Systems Proceedings 
% Stefan Schwarz 
% (c) 2010 by INTHFT
% www.nt.tuwien.ac.at

   properties
       SINR_averager
       CQI_mapping_data
       linprog_options
       alphabets
       av_throughput % exponentially weighted throughputs
%        av_throughput_lin % linearly averaged TP
       Tsub     % subframe duration
       alpha    % alpha parameter for alpha-fair utility functions
       J        % Jain's fairness index
%        stepsize % stepsize for alpha tracking
%        initial_stepsize % initial stepsize set in LTE_load_parameters
%        startup_phase
%        linear_start
%        hi_low
%        sign_change
       cqi_pdf            % empirical cqi pdf for each user - necessary to compute the right alpha value
%        cqi_pdf_lin
%        cqi_pdf_store
%        av
       fairness           % desired fairness (for var. fair scheduler)
       efficiencies       % stores the spectral efficiencies corresponding to each cqi
%        J_exp
       counter
       TP_exp
       last_set
   end

   methods
       function obj = VarFairScheduler(RB_grid_size,Ns_RB,UEs_to_be_scheduled,scheduler_params,CQI_params,averager,mapping_data,alphabets)
           % Fill in basic parameters (handled by the superclass constructor)
           obj = obj@network_elements.lteScheduler(RB_grid_size,Ns_RB,UEs_to_be_scheduled,scheduler_params,CQI_params);         
        
           obj.static_scheduler = false;
           obj.SINR_averager = averager;
           % Get a vector of scheduling params (one for each UE)
           % initialized to the values that we want
           obj.UE_static_params = obj.get_initialized_UE_params(scheduler_params,CQI_params);
           obj.CQI_mapping_data = mapping_data;
%            obj.linprog_options = optimset('LargeScale','off','Simplex','on','Display','off');
           obj.alphabets = alphabets;
           obj.av_throughput = zeros(size(UEs_to_be_scheduled,2),1);
%            obj.av_throughput_lin = zeros(size(UEs_to_be_scheduled,2),obj.av_const);
%            obj.Tsub = Tsub;
           obj.alpha = 0; % Start with best CQI
           obj.J = 1/size(UEs_to_be_scheduled,2);
%            obj.stepsize = scheduler_params.stepsize;
%            obj.initial_stepsize = scheduler_params.stepsize;
%            obj.startup_phase = true;
%            obj.hi_low = 1;
%            obj.sign_change = 0;
           obj.cqi_pdf = zeros(size(UEs_to_be_scheduled,2),16);
%            obj.cqi_pdf_lin = zeros(size(UEs_to_be_scheduled,2),16);
%            obj.cqi_pdf_store = zeros(size(UEs_to_be_scheduled,2),16,obj.av_const);
%            obj.av = 50;
           obj.fairness = scheduler_params.fairness;
           obj.efficiencies = repmat([obj.CQI_params(1).efficiency/2,obj.CQI_params(1:15).efficiency],size(UEs_to_be_scheduled,2),1);
%            obj.J_exp = [];
           obj.counter = 0;
           obj.TP_exp = zeros(size(UEs_to_be_scheduled,2),1);
           obj.last_set = -10^6;
       end

       function UE_scheduling = scheduler_users(obj,subframe_corr,total_no_refsym,SyncUsedElements,UE_output,UE_specific_data,cell_genie,PBCHsyms)
           UE_scheduling = obj.UE_static_params;
           N_RB = size(UE_output(1).CQI,1)*2;
           N_UE = size(UE_output,2);
           
           %% store the cqi pdf
% %            obj.cqi_pdf_lin = obj.cqi_pdf_lin*obj.counter*N_RB;
%            obj.cqi_pdf_store = circshift(obj.cqi_pdf_store,[0,0,-1]);
%            obj.cqi_pdf_store(:,:,end) = 0; 
           pdf_tmp = zeros(N_UE,16);
           pdf_const = obj.av_const;
           for uu = 1:N_UE
               CQI_temp = mod(UE_output(uu).CQI(:),20)+1;
               for rb = 1:N_RB
                    pdf_tmp(uu,CQI_temp(rb)) = pdf_tmp(uu,CQI_temp(rb))+1;
%                     obj.cqi_pdf_store(uu,CQI_temp(rb),end) = obj.cqi_pdf_store(uu,CQI_temp(rb),end)+1;
% %                     obj.cqi_pdf_lin(uu,CQI_temp(rb)) = obj.cqi_pdf_lin(uu,CQI_temp(rb))+1;
               end
               pdf_tmp(uu,:) = pdf_tmp(uu,:)/sum(pdf_tmp(uu,:));
           end
           obj.counter = obj.counter+1;
% %            obj.cqi_pdf_lin = obj.cqi_pdf_lin/(obj.counter*N_RB);
           if obj.counter ~= 1
               obj.cqi_pdf = pdf_tmp*1/pdf_const+obj.cqi_pdf*(1-1/pdf_const);
           else
               obj.cqi_pdf = pdf_tmp;
           end
%            obj.cqi_pdf_lin = sum(obj.cqi_pdf_store(:,:,max(1,end-obj.counter):end),3);
%            obj.cqi_pdf_lin = obj.cqi_pdf_lin/(min(obj.counter,obj.av_const)*N_RB);
              
           %% set pmi and ri values
           [UE_scheduling,c,user_ind] = obj.set_pmi_ri(UE_scheduling,N_UE,N_RB,UE_output);          
           c = c';
           for uu = 1:N_UE
                if ~isempty(find(UE_output(uu).CQI(:) == 20,1))
                    obj.efficiencies(uu,1) = min(c(:,uu));
                end
           end
%            c = zeros(N_RB,N_UE);
%            count = 0;
%            for u_= user_ind % calculate sum efficiencies for both codewords on every RB
%                count = count+1;
%                UE_scheduling(u_).UE_mapping = false(obj.RB_grid_size,2);
%                c(:,count) = sum(reshape([obj.CQI_params(UE_output(u_).CQI(:,:,1:UE_scheduling(u_).nCodewords)).efficiency],obj.RB_grid_size*2,UE_scheduling(u_).nCodewords),2);
%            end % based on this value the decision is carried out which UE gets an RB

           %% update average throughput
           for uu = 1:N_UE
%                [obj.av_throughput(uu),obj.av_throughput_lin(uu,:)] = obj.compute_av_throughput(UE_output(uu),obj.av_throughput(uu),uu,N_UE,obj.av_throughput_lin(uu,:),obj.counter);
               [obj.av_throughput(uu)] = obj.compute_av_throughput(UE_output(uu),obj.av_throughput(uu),uu,N_UE);
           end
%            obj.av_throughput_lin
           %% VF scheduler
           RBs = obj.VF_scheduler(N_UE,N_RB,c,user_ind);
           
           %% set cqi values
           UE_scheduling = obj.set_cqi(UE_scheduling,user_ind,RBs,N_UE,N_RB,UE_output);
           obj.calculate_allocated_bits(UE_scheduling,subframe_corr,total_no_refsym,SyncUsedElements,PBCHsyms); 
           
          end
       
       function RBs = VF_scheduler(obj,N_UE,N_RB,c,user_ind)
           % core scheduling function (same in LL and SL)
           
           obj.alpha_adaptation_pdf(N_UE); % adapt the alpha value to achieve the desired fairness - better not online
%            obj.alpha_adaptation(N_UE); % adapt the alpha value to achieve the desired fairness - online tracking
           
           RB_set = ones(N_RB,1);
           RB_UEs = false(N_RB,N_UE);
           alpha_tmp = obj.alpha(end);
           for rr = 1:N_RB
               res = find(RB_set);
               metric = ones(N_RB,N_UE)*-Inf;
               for r_ = 1:sum(RB_set)
                   for u_ = 1:N_UE
%                        metric(res(r_),u_) = log10(c(res(r_),u_)*12*7)-alpha_tmp*log10(max((1-1/obj.av_const)*obj.av_throughput(user_ind(u_))+1/obj.av_const*RB_UEs(:,u_).'*c(:,u_)*12*7,eps));      % 12*7 equals the number of elements in a RB             
                       metric(res(r_),u_) = log10(c(res(r_),u_)*obj.Ns_RB)-alpha_tmp*log10(max(obj.av_throughput(user_ind(u_)),eps));  
                   end
               end
               maxi = max(metric(:));
               indis = find(metric == maxi);
               ind = indis(randi(length(indis)));
               [temp_res,temp_ue] = ind2sub(size(metric),ind);
               RB_set(temp_res) = 0;
               RB_UEs(temp_res,temp_ue) = true;
           end
           RB_UEs = RB_UEs';
           RBs = RB_UEs(:);
       end
       
%        function alpha_adaptation(obj,N_UE) % function that tries to track the alpha parameter to achieve a given Jain's fairness
%             if sum(obj.av_throughput)
%                J_temp = sum(obj.av_throughput)^2/(N_UE*sum(obj.av_throughput.^2));
%                obj.J = [obj.J,J_temp];
%                if (((J_temp-obj.fairness)*obj.hi_low) > 0 || (obj.alpha(end) < 1 && isequal(obj.hi_low,-1))) && obj.startup_phase % end the startup_phase as soon as the desired fairness is achieved
%                    obj.startup_phase = false;
%                    obj.linear_start = length(obj.J); % store the position of the beginning of the linear tracking phase
%                    obj.drift_detect = 0;
%                    obj.sign_change = length(obj.J);
%                    obj.av = 50;
%                end
%                if obj.startup_phase % in the startup phase the stepsize for alpha is growing exponentially
%                     obj.alpha = [obj.alpha, max(0,obj.alpha(end)-(obj.J(end)-obj.fairness)*obj.stepsize)];
%                     obj.stepsize = obj.stepsize*1.2;  % 1.15 is heuristically determined as a good growth rate 
%                else % in the linear phase the stepsize is adapted according to the variation of the average fairness compared to the desired one
%                     y = mean(obj.J(max(obj.linear_start,end-10):end)); % variable to detect drifts between the actual fairness and the desired one
%                     J_diff=mean(obj.J(max(obj.linear_start,end-obj.av):end))-obj.fairness;  % adapts the stepsize to the variation between the desired J and a long term average J
%                     if ~mod(length(obj.J)-obj.linear_start,20) % adapts the averaging window length for J_diff - increases the window size if the algorithm is able to track J in the linear mode
%                         obj.av = obj.av+10;
%                     end
%                     if (y(end)-obj.fairness)*obj.drift_detect < 0  % detects drifts between the desired and the actual J - if y does not vary around obj.fairness --> there is a drift
%                         obj.sign_change = length(obj.J);
%                     end
%                     obj.drift_detect = y(end)-obj.fairness;
%                     obj.stepsize = abs(J_diff)*max(obj.alpha(end)^2,0.5)*3; % 3 heuristically determined as a good value for tracking channel variations
%                     obj.alpha = [obj.alpha, max(0,obj.alpha(end)-(obj.J(end)-obj.fairness)*obj.stepsize)];
%                      if  ~(J_diff > 0 && obj.alpha(end) < 2) && length(obj.J)-obj.sign_change > 20 % switch back to the startup_phase (exponential phase) if there is a drift in J compared to the desired one
%                         obj.startup_phase = true;
%                         obj.stepsize = obj.initial_stepsize;
%                         if J_diff > 0 % find out wheter J has to go upwards or downwards
%                             obj.hi_low = -1;
%                         else
%                             obj.hi_low = 1;
%                         end
%                     end
%                end
%            end
%        end
       
       function alpha_adaptation_pdf(obj,N_UE) % compute alpha
            if sum(obj.av_throughput)
                J_temp = sum(obj.av_throughput)^2/(N_UE*sum(obj.av_throughput.^2));
%                 TP_lin = mean(obj.av_throughput_lin(:,max(1,end-obj.counter):end),2);
%                 J_temp_lin = sum(TP_lin)^2/(N_UE*sum(TP_lin.^2));
                obj.J = [obj.J,J_temp];
            end
            if  abs(obj.fairness-obj.J(end)) > 0.02 && obj.counter - obj.last_set > 50
                obj.alpha = [obj.alpha,obj.get_alpha(N_UE)];
%             elseif abs(obj.fairness-obj.J(end)) > 0.005
%                 obj.alpha = [obj.alpha,obj.track_alpha];
            else
                obj.alpha = [obj.alpha,obj.alpha(end)];
            end
       end 
       
       function alpha_end = get_alpha(obj,N_UE) % compute a starting value for alpha from the observed CQI pdf
           TP_norm = zeros(N_UE,16);
           av_TP = obj.av_throughput;
%            av_TP = mean(obj.av_throughput_lin(:,max(1,end-obj.counter):end),2);
%            av_TP = filter(1/obj.av_const *ones(obj.av_const,1),1,obj.av_throughput_lin(:,max(1,end-obj.counter):end));
%            av_TP = obj.TP_exp;
           TP_store = av_TP;
           if ~sum(av_TP)
                av_TP = ones(N_UE,1);
                TP_store = [];
           end
           alpha_tmp = obj.alpha(end);
%            alpha_tmp = 0;
           end_it = false;
           count_it = 0;
           J_tmp = [];
           av_temp = obj.av_const*10;
           while ~end_it
               Exp_TP = zeros(N_UE,1);
               count_it = count_it+1;
               for uu = 1:N_UE
%                    TP_norm(uu,:) = obj.efficiencies_lin(uu,:)*(12*7-4-1/5*12)/av_TP(uu)^alpha_tmp(end);
                   TP_norm(uu,:) = obj.efficiencies(uu,:)*(obj.Ns_RB-obj.overhead_ref-1/5*obj.overhead_sync)/av_TP(uu)^alpha_tmp(end);
               end
               TP_norm(isnan(TP_norm)) = 10^5;
               TP_norm(abs(TP_norm) == Inf) = 10^5;
               for uu = 1:N_UE
                   for cqi_i = 1:16
                       P_temp = ones(N_UE,1);
                       for u2 = 1:N_UE
                           if u2 ~= uu
                               indis1 = TP_norm(u2,1:16) < TP_norm(uu,cqi_i);
                               indis2 = TP_norm(u2,1:16) == TP_norm(uu,cqi_i);
                               indis1 = logical(indis1-indis2*round(rand));
                               P_temp(u2) = sum(obj.cqi_pdf(u2,indis1));
%                                P_temp(u2) = sum(obj.cqi_pdf_lin(u2,indis1));
                           end
                       end
%                        Exp_TP(uu) = Exp_TP(uu)+max(0,obj.cqi_pdf(uu,cqi_i)*(8*round(1/8*obj.efficiencies(cqi_i)*(12*7-4-1/5*12)*12*prod(P_temp))-24));
%                        Exp_TP(uu) = Exp_TP(uu)+obj.cqi_pdf_lin(uu,cqi_i)*(obj.efficiencies(cqi_i)*(12*7-4-1/5*12)*12*prod(P_temp)-24);
                        Exp_TP(uu) = Exp_TP(uu)+obj.cqi_pdf(uu,cqi_i)*obj.efficiencies(uu,cqi_i)*prod(P_temp);
%                         Exp_TP(uu) = Exp_TP(uu)+obj.cqi_pdf_lin(uu,cqi_i)*obj.efficiencies(uu,cqi_i)*prod(P_temp);
                   end
                   Exp_TP(uu) = max(0,8*round(1/8*Exp_TP(uu)*(obj.Ns_RB-obj.overhead_ref-1/5*obj.overhead_sync)*obj.RB_grid_size*2)-24);
               end
%                Exp_TP
               TP_store = [TP_store,Exp_TP];
               av_TP = mean(TP_store(:,max(end-av_temp,1):end),2);
%                av_TP = av_TP *(1-1/av_temp)+av_TP*1/av_temp;
               J_tmp = [J_tmp,sum(av_TP)^2/(N_UE*sum((av_TP).^2))];
               if length(alpha_tmp) ~= 1
                   J_diff = abs(J_tmp(end)-J_tmp(end-1));
               else
                   J_diff = 1;
               end
               if (J_diff > 0.00075 || abs(obj.fairness-J_tmp(end)) > 0.00125) && count_it < 5000  % abs(obj.fairness-J_tmp(end)) > 0.005 && count_it < 5000 
                   alpha_tmp = [alpha_tmp,max(0,alpha_tmp(end) + (obj.fairness-J_tmp(end)))];
               else
                   end_it = true;
               end
           end
%            obj.J_exp = [obj.J_exp,J_tmp(end)];
           alpha_end = alpha_tmp(end);
           obj.TP_exp = av_TP;
           obj.last_set = obj.counter;
%            figure(1)
%            plot(alpha_tmp)
%            figure(2)
%            plot(J_tmp)
%            figure(3)
%            plot(TP_store(1,:))
%            hold on
%            plot(TP_store(2,:),'r')
       end
       
       function alpha_end = track_alpha(obj) 
           alpha_end = obj.alpha(end)+(obj.fairness-obj.J(end))*obj.alpha(end)*0.1;
       end
       
   end
end 

