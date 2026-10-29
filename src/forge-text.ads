--  Decimal boundary for the production fixed-point representation.
package Forge.Text with SPARK_Mode is
   function Number (V : Scalar) return String;
   --  Exact decimal expansion, without a floating-point conversion.
   procedure Parse (S : String; V : out Scalar; Ok : out Boolean);
   --  Plain signed decimal, <=64 fractional digits, +/-10,000; ties to even.
end Forge.Text;
