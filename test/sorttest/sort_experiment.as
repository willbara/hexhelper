// Hex Helper sort experiment: records how Flash's Array.sort orders items that compare equal.
var hwaSeed = 12345;
var hwaR = function(n)
{
   hwaSeed = hwaSeed * 16807 % 2147483647;
   return Math.floor(hwaSeed / 2147483647 * n);
};
var hwaOut = "";
var hwaT = 0;
while(hwaT < 400)
{
   var hwaN = 2 + hwaR(30);
   var hwaK = 1 + hwaR(4);
   var hwaArr = new Array();
   var hwaI = 0;
   while(hwaI < hwaN)
   {
      hwaArr.push({k:hwaR(hwaK),id:hwaI});
      hwaI++;
   }
   hwaArr.sort(function(a, b)
   {
      if(a.k > b.k)
      {
         return -1;
      }
      if(a.k < b.k)
      {
         return 1;
      }
      return 0;
   });
   var hwaS = "";
   hwaI = 0;
   while(hwaI < hwaN)
   {
      hwaS += (hwaI != 0 ? "," : "") + hwaArr[hwaI].id;
      hwaI++;
   }
   hwaOut += (hwaT != 0 ? ";" : "") + hwaS;
   hwaT++;
}
var hwaSO = SharedObject.getLocal("hwa_sorttest");
hwaSO.data.result = hwaOut;
hwaSO.data.done = true;
hwaSO.flush();
