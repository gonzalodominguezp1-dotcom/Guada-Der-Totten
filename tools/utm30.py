# Paso de lat/lon (WGS84/ETRS89) a UTM huso 30 (EPSG:25830), para leer el MDT del IGN.
import math
def ll_to_utm30(lat, lon):
    a=6378137.0; f=1/298.257222101; e2=f*(2-f); k0=0.9996; lon0=math.radians(-3.0)
    phi=math.radians(lat); lam=math.radians(lon)
    n=f/(2-f); A=a/(1+n)*(1+n*n/4+n**4/64)
    alpha=[n/2-2*n*n/3+5*n**3/16, 13*n*n/48-3*n**3/5, 61*n**3/240]
    t=math.sinh(math.atanh(math.sin(phi))-2*math.sqrt(n)/(1+n)*math.atanh(2*math.sqrt(n)/(1+n)*math.sin(phi)))
    xi=math.atan2(t, math.cos(lam-lon0)); eta=math.atanh(math.sin(lam-lon0)/math.sqrt(1+t*t))
    E=eta+sum(alpha[j]*math.cos(2*(j+1)*xi)*math.sinh(2*(j+1)*eta) for j in range(3))
    N=xi+sum(alpha[j]*math.sin(2*(j+1)*xi)*math.cosh(2*(j+1)*eta) for j in range(3))
    return 500000+k0*A*E, k0*A*N
