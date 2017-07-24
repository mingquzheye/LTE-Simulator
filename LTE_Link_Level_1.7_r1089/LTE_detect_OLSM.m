function [LLR_SD,M,H_back,rx_layer_x_equalized] = LTE_detect_OLSM(MCS_and_scheduling,rx_user_symbols,H_est_user,LTE_params,BS_nAtPort,receiver,receiver_k,sigma_n2)
% Open-loop Spatial multiplexing detection.
% Author: Stefan Schwarz, sschwarz@nt.tuwien.ac.at
% (c) 2009 by INTHFT
% www.nt.tuwien.ac.at

nLayers = MCS_and_scheduling.nLayers;

rx_layer_x_equalized = zeros(length(rx_user_symbols),nLayers);

M = zeros(1,size(MCS_and_scheduling.CQI_params,2));
for i = 1:size(MCS_and_scheduling.CQI_params,2)
    M(i) = MCS_and_scheduling.CQI_params(i).modulation_order;
end
switch nLayers % when layer number is unequal to codeword number we need to do something
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
LLR_SD = zeros(sum(M),length(rx_user_symbols));   % Log likelihood Ratios of the Spere decoder

l = 1:length(rx_user_symbols);
p = mod(l-1,nLayers)+1;                 % needed for the choice of the precoding matrix (see 3GPP TS 36.213 section 7.1.3)
k = mod(floor((l-1)/nLayers),4)+1;
if (BS_nAtPort == 2)
    period = 2;
else
    period = lcm(seqperiod(k),seqperiod(p));
end
H_back = zeros(l(end),size(H_est_user,2),nLayers);

H_est_user_shiftdim = shiftdim(H_est_user,1); % Dimension shift to make successive calls to "squeeze" unnecessary
for ctr = 1:l(end)
    H_complete = H_est_user_shiftdim(:,:,ctr)*MCS_and_scheduling.PRE(:,:,mod(ctr-1,period)+1);
    H_back(ctr,:,:) = H_complete;
    switch receiver
        case 'SSD'
            rx_layer_x = pinv(H_complete)*rx_user_symbols(ctr,:).';
            [Q,R] = qr(H_complete);  % for SS Decoder
            siz = size(R,2);
            if (siz < size(R,1)) % chop off unnecessary data
                R = R(1:siz,:);
                Q = Q(:,1:siz);
            end
            LLR_SD(:,ctr) = LTE_softsphere(rx_layer_x,rx_user_symbols(ctr,:),Q,R,symbol_alphabet,bittable,nLayers,M);
         case 'SSDKB'
            rx_layer_x = pinv(H_complete)*rx_user_symbols(ctr,:).';
            [Q,R] = qr(H_complete);  % for SS Decoder
            siz = size(R,2);
            if (siz < size(R,1)) % chop off unnecessary data
                R = R(1:siz,:);
                Q = Q(:,1:siz);
            end
            LLR_SD(:,ctr) = LTE_softsphere_kbest(rx_layer_x,rx_user_symbols(ctr,:),Q,R,symbol_alphabet,bittable,nLayers,M,receiver_k);
		case 'ZF'
            inv_temp = pinv(H_complete);
            rx_layer_x = inv_temp*rx_user_symbols(ctr,:).';
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
            rx_layer_x = inv_temp*rx_user_symbols(ctr,:).'; % MMSE receiver
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