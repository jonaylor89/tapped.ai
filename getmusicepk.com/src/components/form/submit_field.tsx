import { useAuth } from '@/context/AuthProvider';
import { EpkForm } from '@/types/epk_form';
import { aiEnhanceBio } from '@/utils/api';
import { addEpkForm } from '@/utils/database';
import { Timestamp } from 'firebase/firestore';
import { useRouter } from 'next/navigation';
import { useState } from 'react';


const SubmitField = ({ formData, updateFormData, onValidation }: {
  formData: { [key: string]: string };
  updateFormData: (key: string, value: any) => void;
  onValidation: (isValid: boolean) => void;
}) => {
  const { authUser } = useAuth();
  const [loading, setLoading] = useState(false);
  const router = useRouter();

  if (!authUser) {
    return (
      <div className="flex items-center justify-center h-screen">
        <div className="text-center">
          <p className="text-lg font-bold text-white mb-4">
            Please login to continue
          </p>
          <button
            onClick={() => router.push('/login')}
            className='tapped_btn_rounded'
          >
            Login
          </button>
        </div>
      </div>
    );
  }

  const handleButtonClick = async () => {
    if (!authUser) {
      return;
    }
    setLoading(true);

    const enhancedBio = await aiEnhanceBio({
      userId: authUser.uid,
    })

    formData['bio'] = enhancedBio;

    console.log({
      userId: authUser.uid,
      epkForm: {
        ...formData,
        userId: authUser.uid,
        timestamp: Timestamp.now(),
      }
    });
    
    await addEpkForm({
      userId: authUser.uid,
      epkForm: {
        ...formData,
        userId: authUser.uid,
        timestamp: Timestamp.now(),
      }
    });
    setLoading(false);
    router.push(`/results?id=${formData.id}`);
  };

  return (
    <div style={{ backgroundColor: '#15242d', height: '100vh' }} className="flex items-center justify-center">
      <div className="text-center">
        <div>
          <p className="text-lg font-bold text-white mb-4">
            ready for your epk?
          </p>
        </div>
        <div className="flex items-center justify-center w-[75%] mx-auto">
          {loading && (
            <div className="flex items-center justify-center">
              <div className="animate-spin rounded-full h-32 w-32 border-t-2 border-b-2 border-gray-900"></div>
            </div>
          )}
          {!loading && (
            <button
              onClick={handleButtonClick}
              className='tapped_btn_rounded'
            >
              let&apos;s get it
            </button>
          )}

        </div>
      </div>
    </div>
  );
};

export default SubmitField;
