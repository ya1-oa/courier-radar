import { dbConfigured } from './_shared.js';

export default function handler(req,res){
  if(req.method!=='GET') return res.status(405).json({error:'GET only'});
  return res.status(200).json({
    ok:true,
    captureConfigured:Boolean(process.env.CAPTURE_TOKEN),
    databaseConfigured:dbConfigured(),
    targetDph:Number(process.env.TARGET_DPH||35)
  });
}
