function [LLR_SD,M,rx_layer_x_equalized] = LTE_detect_CLSM(MCS_and_scheduling,rx_user_symbols,H_est_user,LTE_params,filtering,receiver,receiver_k,sigma_n2)
% Closed-loop spatial multiplexing detection.
% Author: Stefan Schwarz, sschwarz@nt.tuwien.ac.at
% (c) 2009 by INTHFT
% www.nt.tuwien.ac.at

% global ideal_precoding; %NOTE:test purpose for precoding!

nLayers = MCS_and_scheduling.nLayers;

rx_layer_x_equalized = zeros(length(rx_user_symbols),nLayers);
% M = [MCS_and_scheduling.CQI_params.modulation_order];     % does not work sometimes (Matlab bug?)
M = zeros(1,size(MCS_and_scheduling.CQI_params,2));
for i = 1:size(MCS_and_scheduling.CQI_params,2)
    M(i) = MCS_and_scheduling.CQI_params(i).modulation_order;
end
if strcmp(receiver,'MMSE_SIC')
    if nLayers == 1
          receiver = 'MMSE';
    end
end

switch nLayers % when layer number is unequal to codeword number we need to do something
    case 1
        M = M(1);
    case 2
        if(MCS_and_scheduling.nCodewords == 1) % 1 codewords, 2 layers
            M = [M,M];
        end
    case 3  % 2 codewords, 3 layers
        M = [M(1),M(2),M(2)];
    case 4  % 2 codewords, 4 layers
        M = [M(1),M(1),M(2),M(2)];
end
bittable = false(sum(M(1:nLayers)),2^max(M));
symbol_alphabet = zeros(nLayers,2^max(M));
for i = 1:nLayers
    bittable(sum(M(1:i-1))+(1:M(i)),1:2^M(i))=LTE_params.bittable{M(i)}; % Bitmapping table
    symbol_alphabet(i,1:2^M(i))=LTE_params.SymbolAlphabet{M(i)}.'; % Symbol alphabet
end
% LLR_SD = zeros(M(1)*nLayers,length(rx_user_symbols));   % Log likelihood Ratios of the Spere decoder
LLR_SD = zeros(sum(M),length(rx_user_symbols)); 
indices = MCS_and_scheduling.freq_indices;
slots = MCS_and_scheduling.slot_indices;
l = 1:length(rx_user_symbols);
if (strcmp(filtering,'BlockFading'))
     for ctr = 1:LTE_params.Ntot
         for ctr2 = 1:2;
            ind1 = ~(indices-ctr);
            ind2 = ~(slots-ctr2);
            ind = ind1 & ind2;
            if (~ind)
                continue
            end
            H_temp = H_est_user(ind,:,:);
            H_complete = reshape(H_temp(1,:,:),size(H_temp,2),size(H_temp,3))*MCS_and_scheduling.PRE(:,:,ctr2,ctr);
%             if ideal_precoding   % NOTE: Test purpose for precoding!
%                 [U,S,V] = svd(squeeze(H_temp(1,:,:)));
% %                 if mod(ctr,2)
% %                     U = circshift(U,[0,1]);
% %                 end
%                 rx_layer_x = U'* rx_user_symbols(ind,:).';
%                 LLR_SD(:,ind) = LTE_demapper(rx_layer_x,symbol_alphabet,bittable,nLayers,M);
%             else            
            switch receiver
                case 'SSD'
                    rx_layer_x = pinv(H_complete)*rx_user_symbols(ind,:).'; % calculate ZF solution
                    [Q,R] =        qr(H_complete);  % for SS Decoder
                    siz = size(R,2);
                    if (siz < size(R,1)) % chop off unnecessary data
                        R = R(1:siz,:);
                        Q = Q(:,1:siz);
                    end
                    LLR_SD(:,ind) = LTE_softsphere(rx_layer_x,rx_user_symbols(ind,:),Q,R,symbol_alphabet,bittable,nLayers,M);
                case 'SSDKB'
                    rx_layer_x = pinv(H_complete)*rx_user_symbols(ind,:).'; % calculate ZF solution
                    [Q,R] =        qr(H_complete);  % for SS Decoder
                    
                 %   [Q,R,P] = sqrd(H_complete);

                    siz = size(R,2);
                    if (siz < size(R,1)) % chop off unnecessary data
                        R = R(1:siz,:);
                        Q = Q(:,1:siz);
                    end
                    LLR_SD(:,ind) = LTE_softsphere_kbest(rx_layer_x,rx_user_symbols(ind,:),Q,R,symbol_alphabet,bittable,nLayers,M,receiver_k);             
			  case 'ZF'
                    inv_temp = pinv(H_complete);
                    rx_layer_x = inv_temp*rx_user_symbols(ind,:).'; % calculate ZF solution
                    rx_layer_x_equalized(ind,:) = rx_layer_x.';
                    Hg = inv_temp*H_complete;
                    noise_enhancement_tmp = sum(abs(inv_temp).^2,2);
                    noise_enhancement = [];
                    for ii = 1:length(M)
                        noise_enhancement = [noise_enhancement;repmat(noise_enhancement_tmp(ii),M(ii),size(rx_layer_x,2))];
                    end
                    LLR_SD(:,ind) = LTE_demapper(rx_layer_x,symbol_alphabet,bittable,nLayers,M,Hg,noise_enhancement);
                case 'MMSE'
                    temp = H_complete'*H_complete;
                    inv_temp = (temp+sigma_n2*eye(size(temp)))^-1*H_complete';
                    rx_layer_x = inv_temp*rx_user_symbols(ind,:).'; % calculate MMSE solution
                    rx_layer_x_equalized(ind,:) = rx_layer_x.';
                    Hg = inv_temp*H_complete;
                    noise_enhancement_tmp = sum(abs(inv_temp).^2,2);
                    noise_enhancement = [];
                    for ii = 1:length(M)
                        noise_enhancement = [noise_enhancement;repmat(noise_enhancement_tmp(ii),M(ii),size(rx_layer_x,2))];
                    end
                    LLR_SD(:,ind) = LTE_demapper(rx_layer_x,symbol_alphabet,bittable,nLayers,M,Hg,noise_enhancement); 
                case 'MMSE_SIC' % just a hard decision SIC 
                    % choose better stream to decode first
                    [C,first] = max(sum(abs(H_complete).^2,1));
                    if first == 1
                        second = 2;
                        bittab1 = bittable(1:M(first),:);
                        bittab2 = bittable(M(first)+1:M(first)+M(second),:);
                    else
                        second = 1;
                        bittab1 = bittable(M(second)+1:M(second)+M(first),:);
                        bittab2 = bittable(1:M(second),:);
                    end
%                     [E,V]=eig(sigma_n2*eye(2)+H_complete(:,second)*H_complete(:,second)'+H_complete(:,first)*H_complete(:,first)');
%                     inv_temp = H_complete(:,first)'*E*pinv(V)*E';
% %                     inv_temp = H_complete(:,first)'/(sigma_n2*eye(2)+H_complete(:,second)*H_complete(:,second)');
%                     rx1 = inv_temp*rx_user_symbols(ind,:).';
%                     Hg = inv_temp*H_complete(:,first);
%                     noise_enhancement_tmp = sum(abs(inv_temp).^2,2);
%                     noise_enhancement = repmat(noise_enhancement_tmp,M(first),length(rx1));
%                     LLR_temp1 = LTE_demapper(rx1,symbol_alphabet(first,:),bittab1,1,M(first),Hg,noise_enhancement); 
%                     rx1
%                     error('jetzt')
                    temp = H_complete'*H_complete;
                    inv_temp = (temp+sigma_n2*eye(size(temp)))^-1*H_complete';
                    rx_layer_x = inv_temp*rx_user_symbols(ind,:).'; % calculate MMSE solution
                    Hg = inv_temp(first,:)*H_complete(:,first);
                    noise_enhancement_tmp = sum(abs(inv_temp(first,:)).^2,2);
                    noise_enhancement = repmat(noise_enhancement_tmp,M(first),size(rx_layer_x,2));
                    LLR_temp1 = LTE_demapper(rx_layer_x(first,:),symbol_alphabet(first,:),bittab1,1,M(first),Hg,noise_enhancement); 
                    % hard decision
                    symbols1 = symbol_alphabet(1,2.^(0:1:M(first)-1)*(1+sign(LLR_temp1))/2+1);
                    % second stream
                    rx_user_symbols(ind,:) = rx_user_symbols(ind,:)-(H_complete(:,first)*symbols1).';
                    inv_temp = pinv(H_complete(:,second));
                    rx2 = inv_temp*rx_user_symbols(ind,:).';
                    Hg = inv_temp*H_complete(:,second);
                    noise_enhancement_tmp = sum(abs(inv_temp).^2,2);
                    noise_enhancement = repmat(noise_enhancement_tmp,M(second),size(rx2,2));
                    LLR_temp2 = LTE_demapper(rx2,symbol_alphabet(second,:),bittab2,1,M(second),Hg,noise_enhancement); 
                    if first == 1
                        LLR_SD(:,ind) = [LLR_temp1;LLR_temp2];
                    else
                        LLR_SD(:,ind) = [LLR_temp2;LLR_temp1];
                    end
            end
         end
     end
else
    for ctr = 1:l(end)
           H_complete = reshape(H_est_user(ctr,:,:),size(H_est_user,2),size(H_est_user,3))*MCS_and_scheduling.PRE(:,:,slots(ctr),indices(ctr));
           switch receiver
                case 'SSD'
                   rx_layer_x = pinv(H_complete)*rx_user_symbols(ctr,:).'; % calculate ZF solution
                   [Q,R] =        qr(H_complete);  % for SS Decoder
                   siz = size(R,2);
                   if (siz < size(R,1)) % chop off unnecessary data
                       R = R(1:siz,:);
                       Q = Q(:,1:siz);
                   end
                   LLR_SD(:,ctr) = LTE_softsphere(rx_layer_x,rx_user_symbols(ctr,:),Q,R,symbol_alphabet,bittable,nLayers,M);
				case 'SSDKB'
                   rx_layer_x = pinv(H_complete)*rx_user_symbols(ctr,:).'; % calculate ZF solution
                   [Q,R] =        qr(H_complete);  % for SS Decoder
                   siz = size(R,2);
                   if (siz < size(R,1)) % chop off unnecessary data
                       R = R(1:siz,:);
                       Q = Q(:,1:siz);
                   end
                   LLR_SD(:,ctr) = LTE_softsphere_kbest(rx_layer_x,rx_user_symbols(ctr,:),Q,R,symbol_alphabet,bittable,nLayers,M,receiver_k);
				case 'ZF'
                   inv_temp = pinv(H_complete);
                   rx_layer_x = inv_temp*rx_user_symbols(ctr,:).'; % calculate ZF solution
                   rx_layer_x_equalized(ctr,:) = rx_layer_x;
                   Hg = inv_temp*H_complete;
                   noise_enhancement_tmp = sum(abs(inv_temp).^2,2);
                   noise_enhancement = [];
                   for ii = 1:length(M)
                       noise_enhancement = [noise_enhancement;repmat(noise_enhancement_tmp(ii),M(ii),1)];
                   end
                   LLR_SD(:,ctr) = LTE_demapper(rx_layer_x,symbol_alphabet,bittable,nLayers,M,Hg,noise_enhancement);
               case 'MMSE'
                   temp = H_complete'*H_complete;
                   inv_temp = (temp+sigma_n2*eye(size(temp)))^-1*H_complete';
                   rx_layer_x = inv_temp*rx_user_symbols(ctr,:).';  % calculate MMSE solution
                   rx_layer_x_equalized(ctr,:) = rx_layer_x;
                   Hg = inv_temp*H_complete;
                   noise_enhancement_tmp = sum(abs(inv_temp).^2,2);
                   noise_enhancement = [];
                   for ii = 1:length(M)
                       noise_enhancement = [noise_enhancement;repmat(noise_enhancement_tmp(ii),M(ii),1)];
                   end
                   LLR_SD(:,ctr) = LTE_demapper(rx_layer_x,symbol_alphabet,bittable,nLayers,M,Hg,noise_enhancement);
               case 'MMSE_SIC' % just a hard decision SIC 
                    % choose better stream to decode first
                    [C,first] = max(sum(abs(H_complete).^2,1));
                    if first == 1
                        second = 2;
                        bittab1 = bittable(1:M(first),:);
                        bittab2 = bittable(M(first)+1:M(first)+M(second),:);
                    else
                        second = 1;
                        bittab1 = bittable(M(second)+1:M(second)+M(first),:);
                        bittab2 = bittable(1:M(second),:);
                    end
%                     [E,V]=eig(sigma_n2*eye(2)+H_complete(:,second)*H_complete(:,second)'+H_complete(:,first)*H_complete(:,first)');
%                     inv_temp = H_complete(:,first)'*E*pinv(V)*E';
% %                     inv_temp = H_complete(:,first)'/(sigma_n2*eye(2)+H_complete(:,second)*H_complete(:,second)');
%                     rx1 = inv_temp*rx_user_symbols(ind,:).';
%                     Hg = inv_temp*H_complete(:,first);
%                     noise_enhancement_tmp = sum(abs(inv_temp).^2,2);
%                     noise_enhancement = repmat(noise_enhancement_tmp,M(first),length(rx1));
%                     LLR_temp1 = LTE_demapper(rx1,symbol_alphabet(first,:),bittab1,1,M(first),Hg,noise_enhancement); 
%                     rx1
%                     error('jetzt')
                    temp = H_complete'*H_complete;
                    inv_temp = (temp+sigma_n2*eye(size(temp)))^-1*H_complete';
                    rx_layer_x = inv_temp*rx_user_symbols(ctr,:).'; % calculate MMSE solution
                    Hg = inv_temp(first,:)*H_complete(:,first);
                    noise_enhancement_tmp = sum(abs(inv_temp(first,:)).^2,2);
                    noise_enhancement = repmat(noise_enhancement_tmp,M(first),size(rx_layer_x,2));
                    LLR_temp1 = LTE_demapper(rx_layer_x(first,:),symbol_alphabet(first,:),bittab1,1,M(first),Hg,noise_enhancement); 
                    % hard decision
                    symbols1 = symbol_alphabet(1,2.^(0:1:M(first)-1)*(1+sign(LLR_temp1))/2+1);
                    % second stream
                    rx_user_symbols(ctr,:) = rx_user_symbols(ctr,:)-(H_complete(:,first)*symbols1).';
                    inv_temp = pinv(H_complete(:,second));
                    rx2 = inv_temp*rx_user_symbols(ctr,:).';
                    Hg = inv_temp*H_complete(:,second);
                    noise_enhancement_tmp = sum(abs(inv_temp).^2,2);
                    noise_enhancement = repmat(noise_enhancement_tmp,M(second),length(rx2));
                    LLR_temp2 = LTE_demapper(rx2,symbol_alphabet(second,:),bittab2,1,M(second),Hg,noise_enhancement); 
                    if first == 1
                        LLR_SD(:,ctr) = [LLR_temp1;LLR_temp2];
                    else
                        LLR_SD(:,ctr) = [LLR_temp2;LLR_temp1];
                    end
           end
    end
end
