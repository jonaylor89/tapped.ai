import { useEffect, useState } from 'react';
import { storage, auth } from '@/utils/firebase';
import { ref, uploadBytes, getDownloadURL } from 'firebase/storage'
import Image from 'next/image';

const ImageUploadField = ({ formData, updateFormData, onValidation, user }) => {
  const [error, setError] = useState(null);
  const [imagePreviewUrl, setImagePreviewUrl] = useState(user.profilePicture || '');
  const [isUploading, setIsUploading] = useState(false);

  useEffect(() => {
    validateForUI(imagePreviewUrl);
  }, [imagePreviewUrl]);  

  useEffect(() => {
    if (user && user.profilePicture) {
        updateFormData({
            ...formData,
            imageUrl: user.profilePicture,
        });
    }
    }, [user]);

    useEffect(() => {
        justValidate(formData['imageUrl'] || '');
    }, [formData['imageUrl']]);
    
    const justValidate = (url) => {
        if (!url) {
        onValidation(false);
        } else {
        onValidation(true);
        }
    };
  
  const validateForUI = (url) => {
    if (!url) {
      setError('Image is required');
      onValidation(false);
    } else {
      setError(null);
      onValidation(true);
    }
  };

  const handleImageChange = async (e) => {
    const user = auth.currentUser;
    e.preventDefault();
    let file = e.target.files[0];

    if (file) {
        setIsUploading(true);
        
        const fileName = `${new Date().toISOString()}_${file.name}`;
        const imageRef = ref(storage, `epk_images/${user.uid}/${fileName}`);

        try {
            await uploadBytes(imageRef, file);

            const downloadURL = await getDownloadURL(imageRef);
            setImagePreviewUrl(downloadURL);
            updateFormData({
                ...formData,
                imageUrl: downloadURL,
            });
            validateForUI(downloadURL);
        } catch (error) {
            console.error("Error uploading image:", error);
            setError('Failed to upload image. Please try again.');
        } finally {
            setIsUploading(false);
        }
    }
};
  
  return (
    <div className="page flex h-full flex-col items-center justify-center">
        <div className="flex w-full flex-col items-start px-6">
            <h1 className="mb-2 text-2xl font-bold text-white">
                Upload your image:
            </h1>
            <div className="flex w-full justify-center mt-4 mb-4">
                {imagePreviewUrl && (
                    <Image 
                        src={imagePreviewUrl} 
                        alt="Uploaded preview" 
                        height={150}
                        width={150}
                        className="w-1/2 h-auto rounded" />
                )}
            </div>
            <div className="flex h-full w-full items-center justify-center">
                <label
                    className="tapped_btn_rounded white_placeholder w-full appearance-none rounded px-4 py-2 leading-tight text-white focus:bg-white focus:text-black font-semibold focus:outline-none cursor-pointer"
                >
                    Choose Image
                    <input
                        type="file"
                        accept="image/*"
                        onChange={handleImageChange}
                        style={{ opacity: 0, position: 'absolute', zIndex: -1 }}
                        disabled={isUploading}
                    />
                </label>
            </div>
            {error && <p className="mt-2 text-red-500">{error}</p>}
            {isUploading && <p className="mt-2 text-white">Uploading...</p>}
        </div>
    </div>
  );
};

export default ImageUploadField;
