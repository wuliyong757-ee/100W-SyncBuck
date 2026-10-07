%% 100W Sync Buck - TIME-DOMAIN switching simulation (startup + load transient)
%  Verifies: output ripple, load-step transient, soft-start
%  Loop gain anchored to the frequency-domain design (fc=20kHz verified in loop_bode.m)
clear; clc; close all;

Vin=48; L=12e-6; C=422e-6; ESR=4e-3; fsw=300e3; Ts=1/fsw;
Vref=0.8; RFB1=20e3; RFB2=1428.6; Kd=RFB2/(RFB1+RFB2); Vout_nom=12;
Vramp=Vin/15;
wi=4141.2; wz1=2*pi*1118.25; wz2=2*pi*2236.5; wp1=2*pi*94286; wp2=2*pi*150000;

t_ss=1.5e-3;                 % soft-start time (shortened for sim speed; design is 10ms)
t_step=3.5e-3;               % load step instant   3.5ms
Io_lo=4; Io_hi=8;            % 4A -> 8A step (50%->100%)
t_end=5.0e-3;

h=Ts/200; N=round(t_end/h);
x=[0;0;0;0;0];               % [iL; vC; integ; lead1; lead2]
T=zeros(1,N); Vout=zeros(1,N); IL=zeros(1,N); Iload=zeros(1,N);

rhs=@(tt,xx,il) deal_rhs(tt,xx,il,Vin,L,C,ESR,fsw,Vramp,Vref,Kd,wi,wz1,wz2,wp1,wp2,t_ss,Vout_nom);

for k=1:N
  t=(k-1)*h;
  il = Io_lo + (Io_hi-Io_lo)*(t>=t_step);
  T(k)=t; Iload(k)=il;
  vout = x(2)+ESR*(x(1)-il);
  Vout(k)=vout; IL(k)=x(1);
  k1=rhs(t,x,il);
  k2=rhs(t+h/2,x+h/2*k1,il);
  k3=rhs(t+h/2,x+h/2*k2,il);
  k4=rhs(t+h,x+h*k3,il);
  x=x+h/6*(k1+2*k2+2*k3+k4);
end

%% ---- metrics ----
idx_ss = T>2.8e-3 & T<3.5e-3;              % steady state @4A
v_mean = mean(Vout(idx_ss));
v_ripple = max(Vout(idx_ss))-min(Vout(idx_ss));
i_pk = max(IL(idx_ss));
  if v_ripple*1e3<=120, rip_verdict='PASS'; else, rip_verdict='FAIL'; end

idx_tr = T>=t_step;
v_min = min(Vout(idx_tr));
t_rec = NaN;
for k=find(idx_tr)
  if abs(Vout(k)-v_mean)<0.005*v_mean && all(abs(Vout(k:min(k+20000,N))-v_mean)<0.005*v_mean)
    t_rec=(T(k)-t_step)*1e6; break
  end
end

fprintf('==== TIME-DOMAIN RESULTS ====\n');
fprintf('  Steady state (4A load):\n');
fprintf('    Vout mean      = %.4f V   (target 12.000)\n', v_mean);
fprintf('    Ripple pk-pk   = %.2f mV  (spec <= 120 mV)  -> %s\n', v_ripple*1e3, rip_verdict);
fprintf('    iL peak        = %.2f A   (design 9.34 A @8A)\n', i_pk);
fprintf('  Load step 4A -> 8A:\n');
fprintf('    Vout min       = %.4f V\n', v_min);
fprintf('    Deviation      = %.1f mV (%.2f%%)  (spec +/-600 mV)\n', (v_min-v_mean)*1e3, (v_min-v_mean)/v_mean*100);
if ~isnan(t_rec), fprintf('    Recovery       = %.0f us  to +-0.5%% band (spec < 200 us)\n', t_rec); else, fprintf('    Recovery       = did not settle within window\n'); end

f1=figure('Position',[80 60 1050 780],'Color','w');
subplot(3,1,1); plot(T*1e3,Vout,'LineWidth',1.1); grid on; box on;
yline(12,'k--'); yline(12.6,'r:','+5%'); yline(11.4,'r:','-5%');
ylabel('Vout (V)'); title('100W Sync Buck - Startup + 4A\rightarrow8A Load Step');
subplot(3,1,2); plot(T*1e3,IL,'LineWidth',1.1); grid on; box on;
ylabel('iL (A)'); ylim([0 12]);
subplot(3,1,3); plot(T*1e3,Iload,'LineWidth',1.1); grid on; box on;
ylabel('Iload (A)'); xlabel('Time (ms)'); ylim([0 10]);
od=fileparts(mfilename('fullpath')); if isempty(od), od=pwd; end
saveas(f1,fullfile(od,'switching_sim.png'));
fprintf('\nPlot: %s\n', fullfile(od,'switching_sim.png'));

function dx = deal_rhs(t,x,il,Vin,L,C,ESR,fsw,Vramp,Vref,Kd,wi,wz1,wz2,wp1,wp2,t_ss,Vnom)
  iL=x(1); vC=x(2); xi=x(3); x2=x(4); x3=x(5);
  vout = vC + ESR*(iL-il);
  vref_e = Vref*min(t/t_ss,1);
  e = vref_e - Kd*vout;
  y1 = xi;
  d1 = wi*e;
  y2 = (wp1/wz1)*(y1 + (wz1-wp1)*x2);
  d2 = -wp1*x2 + y1;
  y3 = (wp2/wz2)*(y2 + (wz2-wp2)*x3);
  d3 = -wp2*x3 + y2;
  vcomp = y3/Kd;
  s = t*fsw - floor(t*fsw);
  on = vcomp > Vramp*s;
  if on, diL=(Vin-vout)/L; else, diL=-vout/L; end
  dx=[diL; (iL-il)/C; d1; d2; d3];
end
