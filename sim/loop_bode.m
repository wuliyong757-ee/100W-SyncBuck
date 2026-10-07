%% 100W Synchronous Buck - Loop Gain Bode & Phase Margin  (VERIFIED)
%  LM5146 Type-III voltage-mode compensation
%  Run: matlab -batch "loop_bode"
clear; clc; close all;

%% ---------- Power stage ----------
Vin=48; L=12e-6; Co=422e-6; ESR=4e-3; fsw=300e3; Vout=12; VREF=0.8;
w0=1/sqrt(L*Co);  f0=w0/(2*pi);
wesr=1/(ESR*Co);  fesr=wesr/(2*pi);
Rf=Vout/8; Q_full=1/(w0*(L/Rf+ESR*Co));
dIL=Vout*(1-Vout/Vin)/(L*fsw);

%% ---------- Modulator (LM5146 line feedforward) ----------
k_FF=15;                       % = Vin/Vramp, held constant -> loop gain Vin-independent

%% ---------- Type-III compensator placement (per LM5146 datasheet) ----------
fc=20e3;
fz1=0.5*f0;  fz2=f0;           % datasheet: wz1=0.5*wo, wz2=wo
fp1=fesr;    fp2=fsw/2;        % datasheet: wp1=wESR, wp2=wSW/2
wz1=2*pi*fz1; wz2=2*pi*fz2; wp1=2*pi*fp1; wp2=2*pi*fp2; wc=2*pi*fc;

s=1j*wc;
H_fc=(1+s/wesr)/(1+s/(Q_full*w0)+(s/w0)^2);
Gc_need=1/(k_FF*abs(H_fc));
Gc_shape=abs((1+s/wz1)*(1+s/wz2)/((1+s/wp1)*(1+s/wp2)));
wi=Gc_need*wc/Gc_shape;        % integrator unity-gain freq
gm=600e-6;                     % LM5146 EA transconductance (typ)

%% ---------- Component values (LM5146 datasheet Table) ----------
Kmid=(fc/f0)/k_FF;             % = RC1/RFB1
RFB1=20e3;
RFB2=RFB1/((Vout/VREF)-1);
RC1=Kmid*RFB1;
CC1=1/(wz1*RC1);
CC2=1/(wp1*RC1);
CC3=1/(wz2*RFB1);
RC2=1/(wp2*CC3);

fprintf('==== DESIGN ====\n');
fprintf('  f0=%.1fHz  fesr=%.1fHz  Q(8A)=%.2f  dIL=%.2fA (DCM<%.2fA)\n', f0,fesr,Q_full,dIL,dIL/2);
fprintf('  fc=%.0fHz  k_FF=%d  Kmid=(fc/f0)/kFF=%.4f\n', fc,k_FF,Kmid);
fprintf('  |Gc(fc)| need=%.4f (%.2f dB)   wi=%.1f rad/s (fi=%.1f Hz)\n', ...
        Gc_need,20*log10(Gc_need),wi,wi/(2*pi));
fprintf('  |Zcomp(fc)|=|Gc|/gm = %.0f ohm\n', Gc_need/gm);
fprintf('\n  ---- COMPONENTS ----\n');
fprintf('  RFB1 = %.2f kohm     RFB2 = %.1f ohm\n', RFB1/1e3, RFB2);
fprintf('  RC1  = %.2f kohm     RC2  = %.1f ohm\n', RC1/1e3, RC2);
fprintf('  CC1  = %.2f nF       CC2  = %.1f pF      CC3 = %.2f nF\n', CC1*1e9, CC2*1e12, CC3*1e9);
fprintf('  Vout check = %.3f V\n', VREF*(1+RFB1/RFB2));

%% ---------- Sweep (CCM only) ----------
f=logspace(1,6,40000); w=2*pi*f; s=1j*w;
Gc=(wi./s).*(1+s/wz1).*(1+s/wz2)./((1+s/wp1).*(1+s/wp2));
Td=0.5/fsw; Dly=exp(-s*Td);

fprintf('\n==== LOAD SWEEP (CCM, >= %.2fA) ====\n', dIL/2);
loads=[8 6 4 3 2 1.5]; res=zeros(numel(loads),4);
for k=1:numel(loads)
  Io=loads(k); R=Vout/Io; Qx=1/(w0*(L/R+ESR*Co));
  Hx=(1+s/wesr)./(1+s./(Qx*w0)+(s./w0).^2);
  Tx=k_FF*Hx.*Gc;
  mx=20*log10(abs(Tx)); px=unwrap(angle(Tx))*180/pi;
  i1=find(mx(1:end-1)>=0 & mx(2:end)<0,1);
  Txd=Tx.*Dly; pxd=unwrap(angle(Txd))*180/pi; mxd=20*log10(abs(Txd));
  i2=find(mxd(1:end-1)>=0 & mxd(2:end)<0,1);
  if isempty(i1), fprintf('  Io=%.1f Q=%.2f -- no crossing --\n',Io,Qx); continue; end
  res(k,:)=[Io,Qx,f(i2),180+pxd(i2)];
  fprintf('  Io=%4.1fA Q=%5.2f  fc=%6.0fHz  PM(no delay)=%5.1f  PM(Td=Ts/2)=%5.1f\n', ...
          Io,Qx,f(i1),180+px(i1),180+pxd(i2));
end
[pmw,iw]=min(res(:,4));
  if pmw>=45, verdict='PASS (>=45 deg)'; else, verdict='FAIL'; end
  fprintf('\n  WORST PM = %.1f deg @ Io=%.1f A  -> %s\n', pmw,res(iw,1), verdict);

%% ---------- Gain margin ----------
mx=20*log10(abs(k_FF*((1+s/wesr)./(1+s./(Q_full*w0)+(s./w0).^2)).*Gc.*Dly));
px=unwrap(angle(k_FF*((1+s/wesr)./(1+s./(Q_full*w0)+(s./w0).^2)).*Gc.*Dly))*180/pi;
ip=find(px(1:end-1)>-180 & px(2:end)<=-180,1);
if ~isempty(ip), fprintf('  Gain margin = %.1f dB @ %.1f kHz\n', -mx(ip), f(ip)/1e3); end

%% ---------- Plot ----------
f1=figure('Position',[80 60 1050 760],'Color','w');
subplot(2,1,1); hold on; grid on; box on;
for k=1:numel(loads)
  Io=loads(k); R=Vout/Io; Qx=1/(w0*(L/R+ESR*Co));
  Hx=(1+s/wesr)./(1+s./(Qx*w0)+(s./w0).^2);
  plot(f,20*log10(abs(k_FF*Hx.*Gc.*Dly)),'LineWidth',1.2,'DisplayName',sprintf('Io=%.1fA',Io));
end
yline(0,'k--'); xline(fc,'r:'); set(gca,'XScale','log'); xlim([10 1e6]); ylim([-80 80]);
ylabel('Magnitude (dB)'); title('100W Sync Buck Loop Gain  (LM5146 Type-III, incl. Td=Ts/2)');
legend('Location','southwest');
subplot(2,1,2); hold on; grid on; box on;
for k=1:numel(loads)
  Io=loads(k); R=Vout/Io; Qx=1/(w0*(L/R+ESR*Co));
  Hx=(1+s/wesr)./(1+s./(Qx*w0)+(s./w0).^2);
  plot(f,unwrap(angle(k_FF*Hx.*Gc.*Dly))*180/pi,'LineWidth',1.2);
end
yline(-135,'r--','PM=45 deg'); xline(fc,'r:');
set(gca,'XScale','log'); xlim([10 1e6]); ylim([-270 0]);
xlabel('Frequency (Hz)'); ylabel('Phase (deg)');
od=fileparts(mfilename('fullpath')); if isempty(od), od=pwd; end
saveas(f1,fullfile(od,'loop_bode.png'));
fprintf('\nPlot: %s\n', fullfile(od,'loop_bode.png'));
