import { UserModel } from '@/types/user_model';
import { aiEnhanceBio } from '@/utils/api';
import { useEffect, useState } from 'react';

  const EnhancedButton = ({ loading, enhanced, onClick }: {
    loading: boolean;
    enhanced: boolean;
    onClick: () => void;
  }) => {
    if (loading) {
      return <p className='text-white'>loading...</p>
    }

    if (enhanced) {
      return <p className='text-white'>enhanced!</p>
    }

    return (
      <button
        onClick={onClick}
        className='bg-purple-300 text-gray-600 font-extrabold px-4 py-2 rounded-lg'
      >
        Ai-enhance
      </button>
    );
  }

const BioField = ({ formData, updateFormData, onValidation, user }: {
  formData: { [key: string]: any};
  updateFormData: (data: { [key: string]: any }) => void;
  onValidation: (isValid: boolean) => void;
  user: UserModel;
}) => {
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(false);
  const [enhanced, setEnhanced] = useState(false);
  const [bio, setBio] = useState('');

  useEffect(() => {
    if (user && user.bio) {
      updateFormData({
        ...formData,
        bio: user.bio,
      });
      setBio(user.bio);
    }
  }, [user]);

  const validateForUI = (value) => {
    if (value.trim() === '') {
      setError('Bio cannot be empty');
      onValidation(false);
    } else {
      setError(null);
      onValidation(true);
    }
  };

  const justValidate = (value) => {
    if (value.trim() === '') {
      onValidation(false);
    } else {
      onValidation(true);
    }
  };

  useEffect(() => {
    console.log({ bio });
    updateFormData({
      ...formData,
      bio,
    });
    justValidate(bio);
  }, [bio]);


  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setBio(value);
    validateForUI(value);
  };

  const handleAiEnhance = async () => {
    setLoading(true);
    try {
      const betterBio = await aiEnhanceBio({
        userId: user.id,
      });
      setBio(betterBio);
      validateForUI(betterBio);
      setEnhanced(true);
    } catch (e) {
      console.error(e);
    }
    setLoading(false);
  }

  return (
    <div className="page flex h-full flex-col items-center justify-center">
      <div className="flex w-full flex-col items-start">
        <h1 className="mb-2 text-2xl font-bold text-white">
          what&apos;s your bio?
        </h1>
        <div className="flex flex-col h-full w-full items-center justify-center">
          <div className={`white_placeholder w-full appearance-none rounded ${error ? 'border-2 border-red-500' : ''
            } bg-[#63b2fd] px-4 py-2 leading-tight text-white focus:bg-white focus:text-black font-semibold focus:outline-none`}>
            <textarea
              name="bio"
              placeholder="type here..."
              value={bio}
              onChange={handleInputChange}
              className={`min-h-[200px] w-full h-full bg-transparent text-white font-semibold focus:outline-none`}
            />
            <div className='flex justify-end'>
              <EnhancedButton 
                loading={loading} 
                enhanced={enhanced}
                onClick={handleAiEnhance}
              />
            </div>
          </div>
          {error && <p className="mt-2 text-red-500">{error}</p>}
        </div>
      </div>
    </div>
  );
};

export default BioField;
